/**
 * Player entity — handles movement, jumping, dashing, and rendering.
 */
export class Player {
  constructor(canvas, ctx, particles) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.particles = particles;

    // Position (canvas units, set on resize)
    this.x = 0;
    this.y = 0;
    this.vy = 0;
    this.width = 36;
    this.height = 36;

    this.floorY = 0;
    this.dimension = 0;

    // Jump
    this.onGround = false;
    this.jumpStrength = -14;
    this.gravity = 0.55;
    this.maxFalls = 2; // double jump
    this.jumpsLeft = this.maxFalls;

    // Dash
    this.maxDashes = 3;
    this.dashCharges = this.maxDashes;
    this.dashDuration = 0;
    this.DASH_DUR = 14;
    this.dashCooldown = 0;
    this.DASH_COOLDOWN = 120;
    this.dashChargeTimer = 0;
    this.DASH_REGEN = 240;

    // Shift cooldown
    this.shiftCooldown = 0;
    this.SHIFT_COOLDOWN = 12;

    // Invincibility (after dimension shift or dash)
    this.invincible = 0;

    // Visual
    this.angle = 0;
    this.squish = { x: 1, y: 1 };
    this.squishTimer = 0;
    this.glowPulse = 0;
    this.shiftGlow = 0;

    // Trail positions
    this.trail = [];
    this.MAX_TRAIL = 12;

    // State
    this.alive = true;
    this.deathAnim = 0;
  }

  resize(W, H) {
    const floorY = H * 0.8;
    this.floorY = floorY;
    this.x = W * 0.18;
    if (!this.alive) return;
    this.y = floorY - this.height;
  }

  jump(audio) {
    if (!this.alive) return false;
    if (this.jumpsLeft > 0) {
      this.vy = this.jumpStrength;
      if (!this.onGround) {
        this.vy *= 0.88; // second jump slightly weaker
      }
      this.jumpsLeft--;
      this.onGround = false;
      this.squish = { x: 0.75, y: 1.4 };
      this.squishTimer = 8;
      if (audio) audio.playJump();
      return true;
    }
    return false;
  }

  dash(audio) {
    if (!this.alive) return false;
    if (this.dashCharges > 0 && this.dashDuration <= 0) {
      this.dashDuration = this.DASH_DUR;
      this.dashCharges--;
      this.dashCooldown = this.DASH_COOLDOWN;
      this.invincible = this.DASH_DUR + 5;
      if (audio) audio.playDash();
      this.particles.dash(this.x + this.width / 2, this.y + this.height / 2, this.dimension);
      return true;
    }
    return false;
  }

  shiftDimension(to, audio) {
    if (!this.alive) return false;
    if (this.shiftCooldown > 0) return false;
    this.dimension = to;
    this.shiftCooldown = this.SHIFT_COOLDOWN;
    this.shiftGlow = 25;
    this.invincible = Math.max(this.invincible, 8);
    if (audio) audio.playDimensionShift(to);
    this.particles.dimensionShift(
      this.x + this.width / 2,
      this.y + this.height / 2,
      to
    );
    return true;
  }

  update() {
    if (!this.alive) {
      this.deathAnim++;
      return;
    }

    // Gravity
    this.vy += this.gravity;
    this.y += this.vy;

    // Floor collision
    const groundY = this.floorY - this.height;
    if (this.y >= groundY) {
      const wasAirborne = !this.onGround;
      this.y = groundY;
      this.vy = 0;
      if (!this.onGround) {
        this.onGround = true;
        this.jumpsLeft = this.maxFalls;
        this.squish = { x: 1.35, y: 0.7 };
        this.squishTimer = 10;
        if (wasAirborne) {
          this.particles.land(
            this.x + this.width / 2,
            this.floorY,
            this.dimension
          );
        }
      }
    } else {
      this.onGround = false;
    }

    // Dash physics — brief forward boost
    if (this.dashDuration > 0) {
      this.dashDuration--;
      // Visual speed-line particles every other frame
      if (this.dashDuration % 2 === 0) {
        this.particles.dash(
          this.x + this.width / 2,
          this.y + this.height / 2,
          this.dimension
        );
      }
    }

    // Cooldowns
    if (this.shiftCooldown > 0) this.shiftCooldown--;
    if (this.invincible > 0) this.invincible--;
    if (this.dashCooldown > 0) {
      this.dashCooldown--;
    } else if (this.dashCharges < this.maxDashes) {
      this.dashChargeTimer++;
      if (this.dashChargeTimer >= this.DASH_REGEN) {
        this.dashChargeTimer = 0;
        this.dashCharges++;
      }
    }

    // Squish decay
    if (this.squishTimer > 0) {
      this.squishTimer--;
      const t = this.squishTimer / 10;
      this.squish.x = 1 + (this.squish.x - 1) * t;
      this.squish.y = 1 + (this.squish.y - 1) * t;
    } else {
      this.squish = { x: 1, y: 1 };
    }

    // Rotation (slight tilt based on vertical velocity)
    const targetAngle = this.onGround ? 0 : Math.max(-0.25, Math.min(0.25, this.vy * 0.02));
    this.angle += (targetAngle - this.angle) * 0.15;

    // Glow pulse
    this.glowPulse = (this.glowPulse + 0.08) % (Math.PI * 2);
    if (this.shiftGlow > 0) this.shiftGlow--;

    // Trail
    this.trail.unshift({ x: this.x + this.width / 2, y: this.y + this.height / 2 });
    if (this.trail.length > this.MAX_TRAIL) this.trail.pop();

    // Continuous trail particles
    if (Math.random() < 0.35) {
      this.particles.trail(
        this.x + this.width / 2,
        this.y + this.height / 2,
        this.dimension
      );
    }
  }

  die(audio) {
    if (!this.alive) return;
    this.alive = false;
    this.deathAnim = 0;
    if (audio) audio.playDeath();
    this.particles.explode(this.x + this.width / 2, this.y + this.height / 2);
  }

  getHitbox() {
    const margin = 6;
    return {
      x: this.x + margin,
      y: this.y + margin,
      w: this.width - margin * 2,
      h: this.height - margin * 2,
    };
  }

  draw(dim) {
    const ctx = this.ctx;
    const cx = this.x + this.width / 2;
    const cy = this.y + this.height / 2;

    const colors = [
      { primary: '#ff2d78', secondary: '#00f5ff' },
      { primary: '#9d4edd', secondary: '#ffd60a' },
      { primary: '#06ffa5', secondary: '#ffffff' },
    ];
    const col = colors[dim % 3];

    if (!this.alive) {
      if (this.deathAnim < 30) {
        ctx.save();
        ctx.globalAlpha = 1 - this.deathAnim / 30;
        ctx.translate(cx, cy);
        ctx.rotate(this.deathAnim * 0.2);
        const scale = 1 + this.deathAnim * 0.1;
        ctx.scale(scale, scale);
        this._drawBody(ctx, 0, 0, this.width, this.height, col, 0);
        ctx.restore();
      }
      return;
    }

    // Ghost trail
    for (let i = this.trail.length - 1; i >= 0; i--) {
      const t = this.trail[i];
      const alpha = (1 - i / this.MAX_TRAIL) * 0.3;
      ctx.save();
      ctx.globalAlpha = alpha;
      ctx.fillStyle = col.primary;
      ctx.shadowColor = col.primary;
      ctx.shadowBlur = 10;
      const s = (1 - i / this.MAX_TRAIL) * 0.8;
      ctx.beginPath();
      ctx.arc(t.x, t.y, (this.width / 2) * s * 0.5, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    // Invincibility flash
    if (this.invincible > 0 && Math.floor(this.invincible / 3) % 2 === 0) {
      ctx.save();
      ctx.globalAlpha = 0.5;
      ctx.translate(cx, cy);
      ctx.rotate(this.angle);
      ctx.scale(this.squish.x, this.squish.y);
      const gw = this.width * 1.4;
      const gh = this.height * 1.4;
      ctx.shadowColor = col.secondary;
      ctx.shadowBlur = 25;
      ctx.strokeStyle = col.secondary;
      ctx.lineWidth = 2;
      ctx.strokeRect(-gw / 2, -gh / 2, gw, gh);
      ctx.restore();
    }

    // Main body
    const glow = this.shiftGlow > 0
      ? this.shiftGlow * 1.5
      : 8 + Math.sin(this.glowPulse) * 4;

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(this.angle);
    ctx.scale(this.squish.x, this.squish.y);
    this._drawBody(ctx, 0, 0, this.width, this.height, col, glow);
    ctx.restore();
  }

  _drawBody(ctx, cx, cy, w, h, col, glow) {
    const hw = w / 2;
    const hh = h / 2;
    const r = 6; // corner radius

    // Outer glow
    if (glow > 0) {
      ctx.save();
      ctx.shadowColor = col.primary;
      ctx.shadowBlur = glow;
    }

    // Body
    ctx.beginPath();
    ctx.moveTo(cx - hw + r, cy - hh);
    ctx.lineTo(cx + hw - r, cy - hh);
    ctx.quadraticCurveTo(cx + hw, cy - hh, cx + hw, cy - hh + r);
    ctx.lineTo(cx + hw, cy + hh - r);
    ctx.quadraticCurveTo(cx + hw, cy + hh, cx + hw - r, cy + hh);
    ctx.lineTo(cx - hw + r, cy + hh);
    ctx.quadraticCurveTo(cx - hw, cy + hh, cx - hw, cy + hh - r);
    ctx.lineTo(cx - hw, cy - hh + r);
    ctx.quadraticCurveTo(cx - hw, cy - hh, cx - hw + r, cy - hh);
    ctx.closePath();

    const bodyGrad = ctx.createLinearGradient(cx - hw, cy - hh, cx + hw, cy + hh);
    bodyGrad.addColorStop(0, col.primary);
    bodyGrad.addColorStop(1, col.secondary);
    ctx.fillStyle = bodyGrad;
    ctx.fill();

    if (glow > 0) ctx.restore();

    // Inner shine
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.ellipse(cx - hw * 0.2, cy - hh * 0.3, hw * 0.45, hh * 0.22, -0.3, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    // Eyes / core indicator
    ctx.save();
    ctx.fillStyle = '#fff';
    ctx.shadowColor = col.secondary;
    ctx.shadowBlur = 8;
    ctx.beginPath();
    ctx.arc(cx + hw * 0.2, cy - hh * 0.1, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = col.secondary;
    ctx.beginPath();
    ctx.arc(cx + hw * 0.2, cy - hh * 0.1, 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }
}
