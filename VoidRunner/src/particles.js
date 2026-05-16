/**
 * High-performance particle system with object pooling.
 */
export class ParticleSystem {
  constructor(canvas, ctx) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.particles = [];
    this._pool = [];
    this.MAX_PARTICLES = 600;
  }

  _acquire() {
    return this._pool.length > 0 ? this._pool.pop() : {};
  }

  _release(p) {
    this._pool.push(p);
  }

  /**
   * Spawn a burst of particles at (x, y).
   */
  burst(x, y, opts = {}) {
    const {
      count = 12,
      colors = ['#ff2d78', '#00f5ff'],
      minSpeed = 1,
      maxSpeed = 5,
      minLife = 30,
      maxLife = 60,
      minSize = 2,
      maxSize = 5,
      gravity = 0.08,
      spread = Math.PI * 2,
      angle = -Math.PI / 2,
      shape = 'circle',
      glow = true,
    } = opts;

    const toAdd = Math.min(count, this.MAX_PARTICLES - this.particles.length);
    for (let i = 0; i < toAdd; i++) {
      const p = this._acquire();
      const a = angle + (Math.random() - 0.5) * spread;
      const speed = minSpeed + Math.random() * (maxSpeed - minSpeed);
      const life = Math.floor(minLife + Math.random() * (maxLife - minLife));
      p.x = x;
      p.y = y;
      p.vx = Math.cos(a) * speed;
      p.vy = Math.sin(a) * speed;
      p.life = life;
      p.maxLife = life;
      p.size = minSize + Math.random() * (maxSize - minSize);
      p.color = colors[Math.floor(Math.random() * colors.length)];
      p.gravity = gravity;
      p.shape = shape;
      p.glow = glow;
      p.rot = Math.random() * Math.PI * 2;
      p.rotV = (Math.random() - 0.5) * 0.2;
      this.particles.push(p);
    }
  }

  /**
   * Dimension shift — big shockwave ring + colored debris.
   */
  dimensionShift(x, y, dim) {
    const palettes = [
      ['#ff2d78', '#ff6eb0', '#00f5ff', '#fff'],
      ['#9d4edd', '#c77dff', '#ffd60a', '#fff'],
      ['#06ffa5', '#00f5ff', '#ffffff', '#06ffa5'],
    ];
    const colors = palettes[dim % 3];

    this.burst(x, y, {
      count: 30,
      colors,
      minSpeed: 2,
      maxSpeed: 10,
      minLife: 20,
      maxLife: 50,
      minSize: 2,
      maxSize: 6,
      gravity: 0.04,
      glow: true,
    });

    // Ring particles
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * Math.PI * 2;
      const p = this._acquire();
      p.x = x;
      p.y = y;
      p.vx = Math.cos(a) * 6;
      p.vy = Math.sin(a) * 6;
      p.life = 18;
      p.maxLife = 18;
      p.size = 3;
      p.color = colors[i % colors.length];
      p.gravity = 0;
      p.shape = 'circle';
      p.glow = true;
      p.rot = 0;
      p.rotV = 0;
      this.particles.push(p);
    }
  }

  /**
   * Player trail — gentle continuous emission.
   */
  trail(x, y, dim) {
    const colors = [
      ['#ff2d78', '#ff6eb0'],
      ['#9d4edd', '#c77dff'],
      ['#06ffa5', '#00f5ff'],
    ];
    this.burst(x, y, {
      count: 2,
      colors: colors[dim % 3],
      minSpeed: 0.5,
      maxSpeed: 2,
      minLife: 15,
      maxLife: 25,
      minSize: 1.5,
      maxSize: 3,
      gravity: -0.02,
      spread: Math.PI,
      angle: Math.PI,
      glow: false,
    });
  }

  /**
   * Landing impact.
   */
  land(x, y, dim) {
    const colors = [
      ['#ff2d78', '#fff'],
      ['#9d4edd', '#fff'],
      ['#06ffa5', '#fff'],
    ];
    this.burst(x, y, {
      count: 14,
      colors: colors[dim % 3],
      minSpeed: 1,
      maxSpeed: 5,
      minLife: 20,
      maxLife: 35,
      minSize: 2,
      maxSize: 4,
      gravity: 0.15,
      spread: Math.PI * 0.8,
      angle: -Math.PI / 2,
      glow: false,
    });
  }

  /**
   * Dash trail.
   */
  dash(x, y, dim) {
    const colors = [['#00f5ff', '#fff'], ['#ffd60a', '#fff'], ['#fff', '#06ffa5']];
    this.burst(x, y, {
      count: 20,
      colors: colors[dim % 3],
      minSpeed: 1,
      maxSpeed: 6,
      minLife: 15,
      maxLife: 30,
      minSize: 2,
      maxSize: 5,
      gravity: 0,
      spread: Math.PI * 2,
      glow: true,
    });
  }

  /**
   * Death explosion.
   */
  explode(x, y) {
    this.burst(x, y, {
      count: 50,
      colors: ['#ff2d78', '#ff8800', '#ffd60a', '#fff', '#00f5ff'],
      minSpeed: 2,
      maxSpeed: 14,
      minLife: 30,
      maxLife: 80,
      minSize: 2,
      maxSize: 8,
      gravity: 0.12,
      glow: true,
    });
  }

  update() {
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.x += p.vx;
      p.y += p.vy;
      p.vy += p.gravity;
      p.vx *= 0.98;
      p.rot += p.rotV;
      p.life--;
      if (p.life <= 0) {
        this.particles.splice(i, 1);
        this._release(p);
      }
    }
  }

  draw() {
    const ctx = this.ctx;
    for (const p of this.particles) {
      const alpha = p.life / p.maxLife;
      ctx.save();
      ctx.globalAlpha = alpha;
      if (p.glow) {
        ctx.shadowColor = p.color;
        ctx.shadowBlur = p.size * 3;
      }
      ctx.fillStyle = p.color;
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot);
      if (p.shape === 'square') {
        ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size);
      } else {
        ctx.beginPath();
        ctx.arc(0, 0, p.size * alpha * 0.5 + p.size * 0.5, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }
  }

  clear() {
    this.particles.forEach(p => this._release(p));
    this.particles.length = 0;
  }
}
