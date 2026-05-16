/**
 * World renderer — handles backgrounds, floors, and parallax for all 3 dimensions.
 *
 * Dimension 0: NEON CYBER  — dark city, grid floor, neon pink/cyan
 * Dimension 1: VOID REALM  — cosmic purple, floating ruins, gold runes
 * Dimension 2: QUANTUM FLUX — emerald matrix, light-speed trails, white/green
 */
export class WorldRenderer {
  constructor(canvas, ctx) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.dimension = 0;
    this.transitionProgress = 0; // 0..1 (during shift)
    this.transitionFrom = 0;
    this.transitionTo = 0;
    this.shiftTimer = 0;
    this.SHIFT_DUR = 18; // frames

    this.scrollX = 0;

    // Parallax layers per dimension
    this._layers = this._buildLayers();

    // Stars/bg elements
    this._stars = Array.from({ length: 80 }, () => ({
      x: Math.random(),
      y: Math.random() * 0.7,
      r: Math.random() * 1.5 + 0.3,
      speed: Math.random() * 0.0003 + 0.0001,
      opacity: Math.random() * 0.6 + 0.2,
    }));

    // Grid lines for cyberpunk dimension
    this._gridOffset = 0;

    // Floating runes for void dimension
    this._runes = Array.from({ length: 10 }, () => ({
      x: Math.random(),
      y: 0.1 + Math.random() * 0.5,
      size: 12 + Math.random() * 16,
      angle: Math.random() * Math.PI * 2,
      speed: (Math.random() - 0.5) * 0.002,
      opacity: 0.1 + Math.random() * 0.3,
      char: String.fromCodePoint(0x16A0 + Math.floor(Math.random() * 24)),
    }));

    // Matrix rain for quantum
    this._matrixCols = [];
    this._initMatrix();
  }

  _initMatrix() {
    const cols = Math.floor(window.innerWidth / 18);
    this._matrixCols = Array.from({ length: cols }, () => ({
      y: Math.random() * window.innerHeight,
      speed: 1.5 + Math.random() * 2.5,
      opacity: 0.05 + Math.random() * 0.15,
      chars: Array.from({ length: 8 }, () =>
        String.fromCodePoint(0x30A0 + Math.floor(Math.random() * 96))
      ),
      tickTimer: 0,
    }));
  }

  _buildLayers() {
    // Each dimension has layers: { speed (parallax factor), draw(ctx, w, h, offset) }
    return [
      // Dimension 0 — Neon Cyber
      [
        { speed: 0.1, elements: this._genCityLayer(0.1, 0.35, 0.55, '#ff2d78', '#0a0015') },
        { speed: 0.25, elements: this._genCityLayer(0.2, 0.55, 0.72, '#00f5ff', '#0a0015') },
        { speed: 0.5, elements: this._genCityLayer(0.35, 0.68, 0.85, '#ff2d78', '#0a0015') },
      ],
      // Dimension 1 — Void Realm
      [
        { speed: 0.1, elements: this._genRuinLayer(0.08, 0.25, '#9d4edd') },
        { speed: 0.2, elements: this._genRuinLayer(0.15, 0.45, '#ffd60a') },
        { speed: 0.4, elements: this._genRuinLayer(0.25, 0.6, '#9d4edd') },
      ],
      // Dimension 2 — Quantum Flux
      [
        { speed: 0.15, elements: [] },
        { speed: 0.3, elements: [] },
      ],
    ];
  }

  _genCityLayer(heightFactor, minH, maxH, color, bg) {
    const count = 20;
    return Array.from({ length: count }, (_, i) => ({
      x: i / count,
      w: 0.03 + Math.random() * 0.03,
      h: minH + Math.random() * (maxH - minH),
      color,
      windows: Array.from({ length: 6 }, () => ({
        x: Math.random(),
        y: Math.random(),
        on: Math.random() > 0.4,
      })),
    }));
  }

  _genRuinLayer(minH, maxH, color) {
    const count = 8;
    return Array.from({ length: count }, (_, i) => ({
      x: i / count + Math.random() * 0.04,
      w: 0.04 + Math.random() * 0.05,
      h: minH + Math.random() * (maxH - minH),
      color,
      type: Math.random() > 0.5 ? 'pillar' : 'arch',
    }));
  }

  // ─── Transition ───

  startTransition(fromDim, toDim) {
    this.transitionFrom = fromDim;
    this.transitionTo = toDim;
    this.transitionProgress = 0;
    this.shiftTimer = this.SHIFT_DUR;
  }

  update(scrollSpeed, dimension) {
    this.dimension = dimension;
    this.scrollX += scrollSpeed;
    this._gridOffset += scrollSpeed * 0.5;

    // Stars drift
    this._stars.forEach(s => {
      s.x -= s.speed * scrollSpeed * 0.5;
      if (s.x < 0) s.x += 1;
    });

    // Runes drift
    this._runes.forEach(r => {
      r.x -= 0.0008 * scrollSpeed;
      r.angle += r.speed;
      if (r.x < -0.05) r.x += 1.1;
    });

    // Matrix rain
    const W = this.canvas.width;
    const H = this.canvas.height;
    this._matrixCols.forEach(col => {
      col.y += col.speed;
      col.tickTimer++;
      if (col.tickTimer > 6) {
        col.tickTimer = 0;
        col.chars.push(String.fromCodePoint(0x30A0 + Math.floor(Math.random() * 96)));
        col.chars.shift();
      }
      if (col.y > H + 100) col.y = -Math.random() * H;
    });

    // Transition
    if (this.shiftTimer > 0) {
      this.shiftTimer--;
      this.transitionProgress = 1 - this.shiftTimer / this.SHIFT_DUR;
    }
  }

  draw(gameSpeed) {
    const ctx = this.ctx;
    const W = this.canvas.width;
    const H = this.canvas.height;
    const floorY = H * 0.8;

    const dim = this.dimension;
    const shifting = this.shiftTimer > 0;

    if (shifting) {
      this._drawDimension(this.transitionFrom, W, H, floorY, gameSpeed, 1 - this.transitionProgress);
      this._drawDimension(this.transitionTo, W, H, floorY, gameSpeed, this.transitionProgress);
    } else {
      this._drawDimension(dim, W, H, floorY, gameSpeed, 1);
    }
  }

  _drawDimension(dim, W, H, floorY, gameSpeed, alpha) {
    const ctx = this.ctx;
    ctx.save();
    ctx.globalAlpha = alpha;

    if (dim === 0) this._drawCyber(W, H, floorY, gameSpeed);
    else if (dim === 1) this._drawVoid(W, H, floorY, gameSpeed);
    else this._drawQuantum(W, H, floorY, gameSpeed);

    ctx.restore();
  }

  // ─── Dimension 0: Neon Cyber ───

  _drawCyber(W, H, floorY, gameSpeed) {
    const ctx = this.ctx;

    // BG gradient
    const grad = ctx.createLinearGradient(0, 0, 0, H);
    grad.addColorStop(0, '#000010');
    grad.addColorStop(0.6, '#0a0015');
    grad.addColorStop(1, '#15003a');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);

    // Stars
    this._drawStars(W, H, '#ff2d78', '#00f5ff');

    // Perspective grid
    ctx.save();
    ctx.strokeStyle = 'rgba(0,245,255,0.12)';
    ctx.lineWidth = 1;
    const vp = { x: W * 0.5, y: floorY };
    const gridZ = (this.scrollX * 0.5) % 40;
    for (let i = -15; i < 15; i++) {
      ctx.beginPath();
      ctx.moveTo(vp.x + i * W * 0.08, floorY);
      ctx.lineTo(vp.x + i * W * 0.6, H);
      ctx.stroke();
    }
    for (let d = 0; d < 12; d++) {
      const t = ((d * 40 - gridZ) % (12 * 40)) / (12 * 40);
      const y = floorY + (H - floorY) * Math.pow(t, 0.5);
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(W, y);
      ctx.stroke();
    }
    ctx.restore();

    // City silhouettes (parallax layers)
    const layers = this._layers[0];
    layers.forEach((layer, li) => {
      ctx.save();
      const offset = (this.scrollX * layer.speed) % W;
      layer.elements.forEach(el => {
        const bx = ((el.x * W * 3 - offset) % (W * 1.5) + W * 1.5) % (W * 1.5) - W * 0.2;
        const bw = el.w * W;
        const bh = el.h * H;
        const by = floorY - bh;
        ctx.fillStyle = li === 0 ? 'rgba(10,0,21,0.9)' : li === 1 ? 'rgba(5,0,15,0.95)' : '#000';
        ctx.fillRect(bx, by, bw, bh);
        ctx.strokeStyle = el.color;
        ctx.lineWidth = 1;
        ctx.shadowColor = el.color;
        ctx.shadowBlur = 4;
        ctx.strokeRect(bx, by, bw, bh);
        ctx.shadowBlur = 0;

        // Windows
        el.windows.forEach(w => {
          if (!w.on) return;
          const wx = bx + w.x * (bw - 4);
          const wy = by + w.y * (bh - 4);
          ctx.fillStyle = Math.random() > 0.995 ? 'rgba(255,255,100,0.9)' : el.color + '80';
          ctx.fillRect(wx, wy, 3, 3);
        });
      });
      ctx.restore();
    });

    // Neon floor
    ctx.save();
    ctx.shadowColor = '#ff2d78';
    ctx.shadowBlur = 15;
    ctx.strokeStyle = '#ff2d78';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, floorY);
    ctx.lineTo(W, floorY);
    ctx.stroke();
    ctx.shadowColor = '#00f5ff';
    ctx.strokeStyle = 'rgba(0,245,255,0.5)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, floorY + 3);
    ctx.lineTo(W, floorY + 3);
    ctx.stroke();
    ctx.restore();
  }

  // ─── Dimension 1: Void Realm ───

  _drawVoid(W, H, floorY, gameSpeed) {
    const ctx = this.ctx;

    const grad = ctx.createRadialGradient(W * 0.5, H * 0.3, 0, W * 0.5, H * 0.3, W);
    grad.addColorStop(0, '#1a0035');
    grad.addColorStop(0.5, '#0d001f');
    grad.addColorStop(1, '#050010');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);

    // Stars with purple tint
    this._drawStars(W, H, '#9d4edd', '#ffd60a');

    // Floating runes
    this._runes.forEach(r => {
      ctx.save();
      ctx.translate(r.x * W, r.y * H);
      ctx.rotate(r.angle);
      ctx.fillStyle = `rgba(157,78,221,${r.opacity})`;
      ctx.font = `${r.size}px serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.shadowColor = '#9d4edd';
      ctx.shadowBlur = 10;
      ctx.fillText(r.char, 0, 0);
      ctx.restore();
    });

    // Ruins
    const layers = this._layers[1];
    layers.forEach((layer, li) => {
      const offset = (this.scrollX * layer.speed) % W;
      layer.elements.forEach(el => {
        const bx = ((el.x * W * 2.5 - offset) % (W * 1.5) + W * 1.5) % (W * 1.5) - W * 0.2;
        const bh = el.h * H;
        const bw = el.w * W;
        const by = floorY - bh;

        ctx.save();
        ctx.fillStyle = li === 0 ? 'rgba(15,0,35,0.85)' : '#0a0020';
        if (el.type === 'pillar') {
          ctx.fillRect(bx, by, bw, bh);
          ctx.strokeStyle = '#9d4edd';
          ctx.lineWidth = 1;
          ctx.shadowColor = '#9d4edd';
          ctx.shadowBlur = 6;
          ctx.strokeRect(bx, by, bw, bh);
          // Pillar cap
          ctx.fillStyle = '#9d4edd40';
          ctx.fillRect(bx - 4, by, bw + 8, 6);
        } else {
          // Arch
          ctx.fillRect(bx, by + bh * 0.4, bw, bh * 0.6);
          ctx.beginPath();
          ctx.arc(bx + bw / 2, by + bh * 0.4, bw / 2, Math.PI, 0);
          ctx.fill();
          ctx.strokeStyle = '#ffd60a';
          ctx.lineWidth = 1;
          ctx.shadowColor = '#ffd60a';
          ctx.shadowBlur = 8;
          ctx.stroke();
        }
        ctx.restore();
      });
    });

    // Mystical floor
    ctx.save();
    const fg = ctx.createLinearGradient(0, floorY - 20, 0, floorY);
    fg.addColorStop(0, 'transparent');
    fg.addColorStop(1, 'rgba(157,78,221,0.4)');
    ctx.fillStyle = fg;
    ctx.fillRect(0, floorY - 20, W, 22);
    ctx.shadowColor = '#9d4edd';
    ctx.shadowBlur = 20;
    ctx.strokeStyle = '#9d4edd';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, floorY);
    ctx.lineTo(W, floorY);
    ctx.stroke();
    ctx.restore();
  }

  // ─── Dimension 2: Quantum Flux ───

  _drawQuantum(W, H, floorY, gameSpeed) {
    const ctx = this.ctx;

    const grad = ctx.createLinearGradient(0, 0, 0, H);
    grad.addColorStop(0, '#000c08');
    grad.addColorStop(0.7, '#001a0e');
    grad.addColorStop(1, '#002b18');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);

    // Matrix rain
    const colW = W / this._matrixCols.length;
    this._matrixCols.forEach((col, i) => {
      ctx.save();
      ctx.font = `bold ${12}px monospace`;
      col.chars.forEach((ch, ci) => {
        const y = col.y - ci * 16;
        if (y < 0 || y > H) { ctx.restore(); return; }
        const a = ci === 0 ? col.opacity * 3 : col.opacity * (1 - ci / col.chars.length);
        ctx.fillStyle = ci === 0 ? `rgba(255,255,255,${a * 2})` : `rgba(6,255,165,${a})`;
        ctx.fillText(ch, i * colW, y);
      });
      ctx.restore();
    });

    // Stars green
    this._drawStars(W, H, '#06ffa5', '#ffffff');

    // Speed lines
    ctx.save();
    for (let i = 0; i < 12; i++) {
      const sy = (H * 0.1 + i * H * 0.07 + this.scrollX * 0.2 * (0.5 + i * 0.08)) % H;
      const len = 40 + i * 15;
      const opacity = 0.08 + i * 0.015;
      ctx.strokeStyle = `rgba(6,255,165,${opacity})`;
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(W, sy);
      ctx.lineTo(W - len, sy);
      ctx.stroke();
    }
    ctx.restore();

    // Circuit floor
    ctx.save();
    const cg = ctx.createLinearGradient(0, floorY - 10, 0, floorY + 10);
    cg.addColorStop(0, 'rgba(6,255,165,0.6)');
    cg.addColorStop(1, 'transparent');
    ctx.fillStyle = cg;
    ctx.fillRect(0, floorY - 10, W, 12);
    ctx.shadowColor = '#06ffa5';
    ctx.shadowBlur = 25;
    ctx.strokeStyle = '#06ffa5';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(0, floorY);
    ctx.lineTo(W, floorY);
    ctx.stroke();
    // Circuit dots
    ctx.shadowBlur = 6;
    ctx.fillStyle = '#06ffa5';
    const dotSpacing = 30;
    const dotOffset = this.scrollX % dotSpacing;
    for (let x = -dotOffset; x < W + dotSpacing; x += dotSpacing) {
      ctx.beginPath();
      ctx.arc(x, floorY, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  _drawStars(W, H, c1, c2) {
    const ctx = this.ctx;
    this._stars.forEach((s, i) => {
      ctx.save();
      ctx.globalAlpha = s.opacity;
      ctx.fillStyle = i % 3 === 0 ? c1 : i % 3 === 1 ? c2 : '#fff';
      ctx.shadowColor = ctx.fillStyle;
      ctx.shadowBlur = s.r * 4;
      ctx.beginPath();
      ctx.arc(s.x * W, s.y * H, s.r, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    });
  }

  getFloorY(canvasHeight) {
    return canvasHeight * 0.8;
  }

  getDimColors(dim) {
    const palettes = [
      { primary: '#ff2d78', secondary: '#00f5ff', bg: '#0a0015' },
      { primary: '#9d4edd', secondary: '#ffd60a', bg: '#120025' },
      { primary: '#06ffa5', secondary: '#ffffff', bg: '#001a12' },
    ];
    return palettes[dim % 3];
  }
}
