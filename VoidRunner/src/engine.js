/**
 * Core game engine — manages the game loop, state machine,
 * score, difficulty scaling, and glue between all subsystems.
 */
import { WorldRenderer } from './world.js';
import { Player } from './player.js';
import { ObstacleManager } from './obstacles.js';
import { ParticleSystem } from './particles.js';
import { AudioEngine } from './audio.js';

const STATE = {
  MENU: 'menu',
  PLAYING: 'playing',
  PAUSED: 'paused',
  DEAD: 'dead',
  TRANSITION: 'transition',
};

const DIM_NAMES = ['CYBER', 'VOID', 'FLUX'];

export class GameEngine {
  constructor() {
    this.canvas = null;
    this.ctx = null;
    this.state = STATE.MENU;
    this.animId = null;

    // Subsystems
    this.world = null;
    this.player = null;
    this.obstacles = null;
    this.particles = null;
    this.audio = new AudioEngine();

    // Game state
    this.score = 0;
    this.bestScore = parseInt(localStorage.getItem('vr_best') || '0');
    this.multiplier = 1;
    this.combo = 0;
    this.comboTimer = 0;
    this.COMBO_WINDOW = 180;
    this.frameCount = 0;

    // Dimension
    this.dimension = 0;
    this.shiftLocked = false;

    // Speed
    this.baseSpeed = 5;
    this.gameSpeed = this.baseSpeed;
    this.MAX_SPEED = 14;

    // Visual effects
    this.screenShake = 0;
    this.flashColor = null;
    this.flashTimer = 0;
    this.chromAberration = 0;

    // Input
    this._inputBound = false;
    this._swipeStart = null;
    this._doubleTapTimer = 0;
    this._lastTapTime = 0;
    this._tapCount = 0;

    // UI refs
    this.ui = null;
  }

  async init(canvasEl, uiModule) {
    this.canvas = canvasEl;
    this.ctx = canvasEl.getContext('2d');
    this.ui = uiModule;

    await this.audio.init();

    this.particles = new ParticleSystem(this.canvas, this.ctx);
    this.world = new WorldRenderer(this.canvas, this.ctx);
    this.player = new Player(this.canvas, this.ctx, this.particles);
    this.obstacles = new ObstacleManager(this.canvas, this.ctx);

    this._resize();
    window.addEventListener('resize', () => this._resize());

    this._bindInput();
    this._startLoop();
  }

  _resize() {
    const dpr = window.devicePixelRatio || 1;
    const W = window.innerWidth;
    const H = window.innerHeight;
    this.canvas.width = W * dpr;
    this.canvas.height = H * dpr;
    this.canvas.style.width = W + 'px';
    this.canvas.style.height = H + 'px';
    this.ctx.scale(dpr, dpr);
    if (this.player) this.player.resize(W, H);
    if (this.world) this.world.canvas = this.canvas;
    if (this.obstacles) this.obstacles.floorY = H * 0.8;

    // Reinit matrix columns on resize
    if (this.world) this.world._initMatrix();
  }

  get W() { return this.canvas.width / (window.devicePixelRatio || 1); }
  get H() { return this.canvas.height / (window.devicePixelRatio || 1); }

  // ─── Input ───

  _bindInput() {
    if (this._inputBound) return;
    this._inputBound = true;

    // Keyboard
    window.addEventListener('keydown', e => this._handleKey(e));

    // Touch
    const container = document.getElementById('game-container');
    container.addEventListener('touchstart', e => this._handleTouchStart(e), { passive: false });
    container.addEventListener('touchend', e => this._handleTouchEnd(e), { passive: false });
    container.addEventListener('touchmove', e => e.preventDefault(), { passive: false });

    // Click fallback (desktop)
    container.addEventListener('mousedown', e => this._handleMouseDown(e));
    container.addEventListener('mouseup', e => this._handleMouseUp(e));
  }

  _handleKey(e) {
    if (this.state !== STATE.PLAYING) return;
    switch (e.code) {
      case 'ArrowUp':
      case 'Space':
      case 'KeyW':
        e.preventDefault();
        this.player.jump(this.audio);
        break;
      case 'ArrowDown':
      case 'KeyS':
        e.preventDefault();
        this._activateDash();
        break;
      case 'ArrowLeft':
      case 'KeyA':
        this._shiftDim((this.dimension + 2) % 3);
        break;
      case 'ArrowRight':
      case 'KeyD':
        this._shiftDim((this.dimension + 1) % 3);
        break;
      case 'KeyP':
      case 'Escape':
        this.togglePause();
        break;
    }
  }

  _handleTouchStart(e) {
    if (this.state === STATE.MENU || this.state === STATE.DEAD) return;
    if (this.state === STATE.PAUSED) { this.togglePause(); return; }
    const touch = e.changedTouches[0];
    this._swipeStart = { x: touch.clientX, y: touch.clientY, time: Date.now() };
    e.preventDefault();
  }

  _handleTouchEnd(e) {
    if (this.state !== STATE.PLAYING) return;
    const touch = e.changedTouches[0];
    if (!this._swipeStart) return;

    const dx = touch.clientX - this._swipeStart.x;
    const dy = touch.clientY - this._swipeStart.y;
    const dt = Date.now() - this._swipeStart.time;
    const dist = Math.sqrt(dx * dx + dy * dy);
    this._swipeStart = null;

    if (dist < 15 && dt < 300) {
      // Tap
      const now = Date.now();
      if (now - this._lastTapTime < 250) {
        this._activateDash();
        this._lastTapTime = 0;
      } else {
        this._lastTapTime = now;
        const side = touch.clientX < this.W / 2 ? 'left' : 'right';
        if (side === 'left') {
          this.player.jump(this.audio);
        } else {
          this.player.jump(this.audio);
        }
      }
      return;
    }

    // Swipe gesture
    if (Math.abs(dy) > Math.abs(dx) * 1.2) {
      if (dy < -20) {
        // Swipe up — jump
        this.player.jump(this.audio);
      } else if (dy > 20) {
        // Swipe down — dash
        this._activateDash();
      }
    } else if (Math.abs(dx) > 30) {
      if (dx > 0) {
        this._shiftDim((this.dimension + 1) % 3);
      } else {
        this._shiftDim((this.dimension + 2) % 3);
      }
    }
    e.preventDefault();
  }

  _handleMouseDown(e) {
    this._swipeStart = { x: e.clientX, y: e.clientY, time: Date.now() };
  }

  _handleMouseUp(e) {
    if (this.state !== STATE.PLAYING) return;
    if (!this._swipeStart) return;
    const dx = e.clientX - this._swipeStart.x;
    const dy = e.clientY - this._swipeStart.y;
    this._swipeStart = null;

    if (Math.abs(dx) > Math.abs(dy) * 1.2 && Math.abs(dx) > 20) {
      if (dx > 0) this._shiftDim((this.dimension + 1) % 3);
      else this._shiftDim((this.dimension + 2) % 3);
    } else if (dy < -20) {
      this.player.jump(this.audio);
    } else if (dy > 20) {
      this._activateDash();
    } else {
      this.player.jump(this.audio);
    }
  }

  _shiftDim(to) {
    if (this.dimension === to) return;
    const from = this.dimension;
    this.dimension = to;
    this.player.shiftDimension(to, this.audio);
    this.world.startTransition(from, to);
    this.chromAberration = 15;
    this.ui.updateDimension(to, DIM_NAMES[to]);
    this.audio.changeDimMusic(to);

    this._addCombo();
  }

  _activateDash() {
    this.player.dash(this.audio);
  }

  _addCombo() {
    this.combo++;
    this.comboTimer = this.COMBO_WINDOW;
    this.multiplier = 1 + Math.min(4, Math.floor(this.combo / 3)) * 0.5;
    this.ui.updateMultiplier(this.multiplier, this.combo);
    this.audio.playScore(this.combo);
  }

  // ─── Game flow ───

  startGame() {
    this.state = STATE.PLAYING;
    this.score = 0;
    this.multiplier = 1;
    this.combo = 0;
    this.comboTimer = 0;
    this.dimension = 0;
    this.gameSpeed = this.baseSpeed;
    this.frameCount = 0;
    this.screenShake = 0;
    this.chromAberration = 0;

    this.player.resize(this.W, this.H);
    this.player.dimension = 0;
    this.player.alive = true;
    this.player.vy = 0;
    this.player.y = this.H * 0.8 - this.player.height;
    this.player.trail = [];
    this.player.dashCharges = this.player.maxDashes;
    this.player.invincible = 0;
    this.player.shiftCooldown = 0;

    this.obstacles.reset(this.W, this.H);
    this.particles.clear();

    this.audio.resume();
    this.audio.startBgMusic(0);

    this.ui.showHUD(this.player.maxDashes);
    this.ui.updateDimension(0, DIM_NAMES[0]);
    this.ui.updateScore(0);
    this.ui.updateMultiplier(1, 0);
    this.ui.updateDashCharges(this.player.maxDashes, this.player.maxDashes);
  }

  togglePause() {
    if (this.state === STATE.PLAYING) {
      this.state = STATE.PAUSED;
      this.ui.showPause();
      this.audio.stopBgMusic();
    } else if (this.state === STATE.PAUSED) {
      this.state = STATE.PLAYING;
      this.ui.hidePause();
      this.audio.resume();
      this.audio.startBgMusic(this.dimension);
    }
  }

  _die() {
    this.state = STATE.DEAD;
    this.player.die(this.audio);
    this.screenShake = 30;
    this.audio.stopBgMusic();

    const newBest = this.score > this.bestScore;
    if (newBest) {
      this.bestScore = this.score;
      localStorage.setItem('vr_best', this.bestScore);
    }

    setTimeout(() => {
      this.ui.showGameOver(this.score, this.bestScore, newBest);
    }, 900);
  }

  // ─── Main loop ───

  _startLoop() {
    const loop = () => {
      this.animId = requestAnimationFrame(loop);
      this._update();
      this._draw();
    };
    loop();
  }

  _update() {
    if (this.state !== STATE.PLAYING) return;

    this.frameCount++;

    // Speed ramp
    const speedTarget = this.baseSpeed + (this.MAX_SPEED - this.baseSpeed) * Math.min(1, this.score / 3000);
    this.gameSpeed += (speedTarget - this.gameSpeed) * 0.002;

    // Score (distance-based + multiplier)
    this.score += this.gameSpeed * 0.04 * this.multiplier;
    this.ui.updateScore(Math.floor(this.score));

    // Combo decay
    if (this.comboTimer > 0) {
      this.comboTimer--;
      if (this.comboTimer === 0) {
        this.combo = 0;
        this.multiplier = 1;
        this.ui.updateMultiplier(1, 0);
      }
    }

    // Dash charge UI
    this.ui.updateDashCharges(this.player.dashCharges, this.player.maxDashes);

    // Safe dim hint
    if (this.frameCount % 12 === 0) {
      const safeDim = this.obstacles.getSafeDimHint(this.player.x, 320);
      this.ui.updateHint(safeDim, this.dimension);
    }

    // Update subsystems
    this.world.update(this.gameSpeed, this.dimension);
    this.player.update();
    this.obstacles.update(this.gameSpeed, this.gameSpeed, this.W, this.H, this.dimension, this.score);
    this.particles.update();

    // Collision
    if (this.player.alive) {
      const hit = this.obstacles.checkCollision(this.player, this.dimension);
      if (hit && hit.type === 'hit') {
        this._die();
        return;
      }

      // Portal collection
      const portal = this.obstacles.checkPortal(this.player);
      if (portal) {
        this._shiftDim(portal.dim);
        this.score += 50;
        this.particles.burst(
          portal.x, portal.y,
          { count: 20, colors: ['#ffd60a', '#fff'], glow: true, minSpeed: 2, maxSpeed: 8, minLife: 20, maxLife: 40 }
        );
        this.audio.playScore(5);
      }
    }

    // Visual effects decay
    if (this.screenShake > 0) this.screenShake *= 0.85;
    if (this.chromAberration > 0) this.chromAberration--;
    if (this.flashTimer > 0) this.flashTimer--;
  }

  _draw() {
    const ctx = this.ctx;
    const W = this.W;
    const H = this.H;

    ctx.save();

    // Screen shake
    if (this.screenShake > 1) {
      const sx = (Math.random() - 0.5) * this.screenShake;
      const sy = (Math.random() - 0.5) * this.screenShake;
      ctx.translate(sx, sy);
    }

    // Clear
    ctx.clearRect(-20, -20, W + 40, H + 40);

    // World BG
    if (this.state !== STATE.MENU) {
      this.world.draw(this.gameSpeed);
    } else {
      // Menu — show dim 0 softly
      ctx.save();
      ctx.globalAlpha = 0.4;
      this.world.draw(this.baseSpeed * 0.5);
      ctx.restore();
    }

    // Chromatic aberration effect during dim shift
    if (this.chromAberration > 0 && this.state === STATE.PLAYING) {
      const t = this.chromAberration / 15;
      ctx.save();
      ctx.globalCompositeOperation = 'screen';
      ctx.globalAlpha = t * 0.15;
      ctx.translate(t * 4, 0);
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(0, 0, W, H);
      ctx.translate(-t * 8, 0);
      ctx.fillStyle = '#0000ff';
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    }

    if (this.state === STATE.PLAYING || this.state === STATE.DEAD || this.state === STATE.PAUSED) {
      this.obstacles.draw(this.dimension);
      this.player.draw(this.dimension);
      this.particles.draw();
    }

    ctx.restore();
  }
}
