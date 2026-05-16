/**
 * Obstacle & collectible system with procedural generation.
 *
 * Core design: each obstacle has a "safe dimension" — in that dimension it's a
 * platform/passable; in the other two it's deadly. The player must shift
 * dimensions intelligently to survive.
 *
 * Obstacle types:
 *  - wall       : full-height block — must jump over or dimension-shift
 *  - spike      : low spike cluster — must jump over
 *  - laser      : horizontal laser at mid-height — must duck or shift
 *  - float      : floating block with gap below — must time jump
 *  - portal     : bonus ring — walk through for score boost
 *  - platform   : elevated platform (part of gap challenge)
 */
export class ObstacleManager {
  constructor(canvas, ctx) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.obstacles = [];
    this.portals = [];

    this.scrollX = 0;
    this.spawnTimer = 0;
    this.SPAWN_INTERVAL_BASE = 90;
    this.SPAWN_INTERVAL_MIN = 42;
    this.lastObstacleX = 0;

    this.SAFE_PASSAGE = 200; // px gap between obstacles

    this._patternsBuilt = false;
    this._patternQueue = [];
    this._gapTimer = 0;

    this.floorY = 0;
  }

  reset(W, H) {
    this.obstacles.length = 0;
    this.portals.length = 0;
    this.scrollX = 0;
    this.spawnTimer = 0;
    this.lastObstacleX = W * 1.2;
    this.floorY = H * 0.8;
    this._patternQueue = [];
    this._gapTimer = 0;
  }

  update(scrollSpeed, gameSpeed, W, H, currentDimension, score) {
    this.scrollX += scrollSpeed;
    this.floorY = H * 0.8;

    const difficulty = Math.min(1, score / 2000);
    const spawnInterval = Math.round(
      this.SPAWN_INTERVAL_BASE - difficulty * (this.SPAWN_INTERVAL_BASE - this.SPAWN_INTERVAL_MIN)
    );

    // Move and cull
    for (let i = this.obstacles.length - 1; i >= 0; i--) {
      const o = this.obstacles[i];
      o.x -= scrollSpeed;
      // Update bobbing position for float obstacles (used by both collision and draw)
      if (o.type === 'float') {
        o._displayY = o.y + Math.sin((Date.now() * 0.002) + o.bobOffset) * o.bobAmp;
      }
      if (o.x + o.w + 50 < 0) this.obstacles.splice(i, 1);
    }
    for (let i = this.portals.length - 1; i >= 0; i--) {
      const p = this.portals[i];
      p.x -= scrollSpeed;
      p.angle += 0.04;
      if (p.x < -60) this.portals.splice(i, 1);
    }

    // Spawn
    this.spawnTimer++;
    const rightmostX = this.obstacles.reduce((m, o) => Math.max(m, o.x + o.w), 0);
    if (this.spawnTimer >= spawnInterval && rightmostX < W * 0.85) {
      this.spawnTimer = 0;
      this._spawnPattern(W, H, difficulty, currentDimension);
    }

    // Portals (less frequent)
    if (Math.random() < 0.003) {
      this.portals.push({
        x: W + 40,
        y: this.floorY - 80 - Math.random() * 120,
        r: 22,
        angle: 0,
        dim: Math.floor(Math.random() * 3),
      });
    }
  }

  _spawnPattern(W, H, difficulty, currentDim) {
    const type = this._pickType(difficulty);
    const spawnX = W + 60;
    const floorY = this.floorY;

    switch (type) {
      case 'spike': {
        const n = 1 + Math.floor(difficulty * 3);
        for (let i = 0; i < n; i++) {
          this.obstacles.push({
            type: 'spike',
            x: spawnX + i * 28,
            y: floorY - 28,
            w: 24,
            h: 28,
            safeDim: Math.floor(Math.random() * 3),
            dim: (currentDim + 1 + Math.floor(Math.random() * 2)) % 3,
          });
        }
        break;
      }
      case 'wall': {
        const wallH = 60 + Math.random() * 60;
        this.obstacles.push({
          type: 'wall',
          x: spawnX,
          y: floorY - wallH,
          w: 28,
          h: wallH,
          safeDim: Math.floor(Math.random() * 3),
          hasGap: difficulty > 0.4 && Math.random() > 0.5,
          gapY: floorY - wallH * 0.5 - 20,
        });
        break;
      }
      case 'laser': {
        const laserY = floorY - 50 - Math.random() * 60;
        this.obstacles.push({
          type: 'laser',
          x: spawnX,
          y: laserY,
          w: 60 + difficulty * 80,
          h: 8,
          safeDim: Math.floor(Math.random() * 3),
          pulse: 0,
        });
        break;
      }
      case 'float': {
        const platY = floorY - 90 - Math.random() * 80;
        this.obstacles.push({
          type: 'float',
          x: spawnX,
          y: platY,
          w: 80 + difficulty * 40,
          h: 18,
          safeDim: Math.floor(Math.random() * 3),
          bobOffset: Math.random() * Math.PI * 2,
          bobAmp: 12,
        });
        // Spikes below it sometimes
        if (difficulty > 0.35 && Math.random() > 0.5) {
          this.obstacles.push({
            type: 'spike',
            x: spawnX + 20,
            y: floorY - 28,
            w: 24,
            h: 28,
            safeDim: Math.floor(Math.random() * 3),
          });
        }
        break;
      }
      case 'combo': {
        // Wall + laser combo
        const wH = 55 + Math.random() * 40;
        this.obstacles.push({
          type: 'wall',
          x: spawnX,
          y: floorY - wH,
          w: 24,
          h: wH,
          safeDim: 0,
        });
        this.obstacles.push({
          type: 'laser',
          x: spawnX + 80,
          y: floorY - 60,
          w: 50,
          h: 8,
          safeDim: 1,
          pulse: 0,
        });
        break;
      }
      default:
        break;
    }
  }

  _pickType(difficulty) {
    const r = Math.random();
    if (difficulty < 0.2) {
      return r < 0.6 ? 'spike' : 'wall';
    } else if (difficulty < 0.5) {
      if (r < 0.35) return 'spike';
      if (r < 0.6) return 'wall';
      if (r < 0.8) return 'laser';
      return 'float';
    } else {
      if (r < 0.25) return 'spike';
      if (r < 0.45) return 'wall';
      if (r < 0.6) return 'laser';
      if (r < 0.75) return 'float';
      return 'combo';
    }
  }

  checkCollision(player, dimension) {
    if (player.invincible > 0) return false;
    const hb = player.getHitbox();

    for (const o of this.obstacles) {
      // Floating platform is safe in any dim when standing on top
      if (o.type === 'float') {
        const dy = o._displayY !== undefined ? o._displayY : o.y;
        // Check if player lands on top
        if (
          hb.x + hb.w > o.x &&
          hb.x < o.x + o.w &&
          hb.y + hb.h >= dy - 2 &&
          hb.y + hb.h <= dy + 10 &&
          player.vy >= 0
        ) {
          return { type: 'land', obstacle: o };
        }
        // Hitting sides or bottom is a collision only if not safe dim
        if (o.safeDim !== dimension) {
          if (this._rectOverlap(hb, { x: o.x, y: dy, w: o.w, h: o.h })) {
            if (!(hb.y + hb.h >= dy - 2 && hb.y + hb.h <= dy + 10 && player.vy >= 0)) {
              return { type: 'hit', obstacle: o };
            }
          }
        }
        continue;
      }

      // Safe dimension — skip collision
      if (o.safeDim === dimension) continue;

      // Laser — only deadly if player is at same height
      if (o.type === 'laser') {
        if (this._rectOverlap(hb, { x: o.x, y: o.y, w: o.w, h: o.h })) {
          return { type: 'hit', obstacle: o };
        }
        continue;
      }

      // Wall with gap
      if (o.type === 'wall' && o.hasGap) {
        const topPart = { x: o.x, y: o.y, w: o.w, h: o.gapY - o.y };
        const botPart = { x: o.x, y: o.gapY + 30, w: o.w, h: o.y + o.h - (o.gapY + 30) };
        if (this._rectOverlap(hb, topPart) || this._rectOverlap(hb, botPart)) {
          return { type: 'hit', obstacle: o };
        }
        continue;
      }

      if (this._rectOverlap(hb, { x: o.x, y: o.y, w: o.w, h: o.h })) {
        return { type: 'hit', obstacle: o };
      }
    }
    return false;
  }

  checkPortal(player) {
    const cx = player.x + player.width / 2;
    const cy = player.y + player.height / 2;
    for (let i = this.portals.length - 1; i >= 0; i--) {
      const p = this.portals[i];
      const dx = cx - p.x;
      const dy = cy - p.y;
      if (Math.sqrt(dx * dx + dy * dy) < p.r + 12) {
        this.portals.splice(i, 1);
        return p;
      }
    }
    return null;
  }

  _rectOverlap(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
  }

  draw(dimension) {
    const ctx = this.ctx;

    // Draw portals
    for (const p of this.portals) {
      this._drawPortal(p);
    }

    // Draw obstacles
    for (const o of this.obstacles) {
      const isSafe = o.safeDim === dimension;
      this._drawObstacle(o, isSafe, dimension);
    }
  }

  _drawObstacle(o, isSafe, activeDim) {
    const ctx = this.ctx;
    const dim = o.safeDim;

    const dimColors = [
      { dead: '#ff2d78', safe: '#ff2d7840', glow: '#ff2d78' },
      { dead: '#9d4edd', safe: '#9d4edd40', glow: '#9d4edd' },
      { dead: '#06ffa5', safe: '#06ffa540', glow: '#06ffa5' },
    ];
    const c = dimColors[dim % 3];
    const color = isSafe ? c.safe : c.dead;
    const glowColor = c.glow;

    ctx.save();

    if (!isSafe) {
      ctx.shadowColor = glowColor;
      ctx.shadowBlur = 10 + Math.sin(Date.now() * 0.005) * 4;
    }

    if (o.type === 'spike') {
      ctx.fillStyle = color;
      ctx.strokeStyle = isSafe ? 'transparent' : glowColor;
      ctx.lineWidth = 1;
      const n = Math.ceil(o.w / 24);
      for (let i = 0; i < n; i++) {
        const sx = o.x + i * 24;
        ctx.beginPath();
        ctx.moveTo(sx, o.y + o.h);
        ctx.lineTo(sx + 12, o.y);
        ctx.lineTo(sx + 24, o.y + o.h);
        ctx.closePath();
        ctx.fill();
        if (!isSafe) ctx.stroke();
      }
    } else if (o.type === 'wall') {
      ctx.fillStyle = color;
      ctx.strokeStyle = isSafe ? 'transparent' : glowColor;
      ctx.lineWidth = 2;

      if (o.hasGap) {
        // Top section
        ctx.fillRect(o.x, o.y, o.w, o.gapY - o.y);
        if (!isSafe) ctx.strokeRect(o.x, o.y, o.w, o.gapY - o.y);
        // Bottom section
        const botY = o.gapY + 30;
        const botH = o.y + o.h - botY;
        if (botH > 0) {
          ctx.fillRect(o.x, botY, o.w, botH);
          if (!isSafe) ctx.strokeRect(o.x, botY, o.w, botH);
        }
        // Gap indicator
        if (isSafe) {
          ctx.fillStyle = glowColor + '60';
          ctx.fillRect(o.x, o.gapY - 2, o.w, 34);
        }
      } else {
        ctx.fillRect(o.x, o.y, o.w, o.h);
        if (!isSafe) ctx.strokeRect(o.x, o.y, o.w, o.h);
      }

      // Warning stripes on deadly walls
      if (!isSafe) {
        ctx.globalAlpha = 0.2;
        ctx.fillStyle = '#000';
        for (let i = 0; i < o.h; i += 16) {
          if (Math.floor(i / 16) % 2 === 0) {
            ctx.fillRect(o.x, o.y + i, o.w, 8);
          }
        }
        ctx.globalAlpha = 1;
      }
    } else if (o.type === 'laser') {
      o.pulse = (o.pulse || 0) + 0.08;
      const alpha = isSafe ? 0.15 : 0.7 + Math.sin(o.pulse) * 0.3;
      ctx.globalAlpha = alpha;
      ctx.fillStyle = isSafe ? c.safe : glowColor;
      ctx.fillRect(o.x, o.y - 3, o.w, o.h + 6);
      if (!isSafe) {
        ctx.globalAlpha = 0.4;
        ctx.fillStyle = '#fff';
        ctx.fillRect(o.x, o.y + 1, o.w, o.h - 2);
        // Emitter caps
        ctx.globalAlpha = 1;
        ctx.fillStyle = glowColor;
        ctx.fillRect(o.x - 6, o.y - 6, 10, o.h + 12);
        ctx.fillRect(o.x + o.w - 4, o.y - 6, 10, o.h + 12);
      }
    } else if (o.type === 'float') {
      const drawY = o._displayY !== undefined ? o._displayY : o.y;
      ctx.fillStyle = color;
      ctx.strokeStyle = isSafe ? 'transparent' : glowColor;
      ctx.lineWidth = 2;
      ctx.fillRect(o.x, drawY, o.w, o.h);
      if (!isSafe) {
        ctx.strokeRect(o.x, drawY, o.w, o.h);
        // Underside glow
        const ug = ctx.createLinearGradient(0, drawY + o.h, 0, drawY + o.h + 20);
        ug.addColorStop(0, glowColor + '60');
        ug.addColorStop(1, 'transparent');
        ctx.fillStyle = ug;
        ctx.fillRect(o.x, drawY + o.h, o.w, 20);
      }
    }

    ctx.restore();
  }

  _drawPortal(p) {
    const ctx = this.ctx;
    const dimColors = ['#ff2d78', '#9d4edd', '#06ffa5'];
    const color = dimColors[p.dim % 3];

    ctx.save();
    ctx.translate(p.x, p.y);

    // Outer ring
    for (let i = 3; i >= 1; i--) {
      ctx.beginPath();
      ctx.arc(0, 0, p.r + i * 5, 0, Math.PI * 2);
      ctx.strokeStyle = color + Math.floor(40 / i).toString(16).padStart(2, '0');
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // Spinning ring
    ctx.rotate(p.angle);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      ctx.save();
      ctx.rotate(a);
      ctx.shadowColor = color;
      ctx.shadowBlur = 10;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(p.r, 0, 4, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    // Inner glow
    const ig = ctx.createRadialGradient(0, 0, 0, 0, 0, p.r);
    ig.addColorStop(0, color + 'aa');
    ig.addColorStop(1, 'transparent');
    ctx.rotate(-p.angle);
    ctx.fillStyle = ig;
    ctx.beginPath();
    ctx.arc(0, 0, p.r, 0, Math.PI * 2);
    ctx.fill();

    ctx.restore();
  }

  getSafeDimHint(x, lookahead = 250) {
    const upcoming = this.obstacles.filter(
      o => o.x > x && o.x < x + lookahead
    );
    if (upcoming.length === 0) return -1;
    return upcoming[0].safeDim;
  }
}
