/**
 * UI module — manages all DOM overlay screens and HUD updates.
 */
export class UIManager {
  constructor(engine) {
    this.engine = engine;

    this.$startScreen = document.getElementById('start-screen');
    this.$hudEl = document.getElementById('hud');
    this.$gameoverScreen = document.getElementById('gameover-screen');
    this.$pauseScreen = document.getElementById('pause-screen');

    this.$scoreEl = document.getElementById('hud-score');
    this.$multiplierEl = document.getElementById('hud-multiplier');
    this.$comboEl = document.getElementById('hud-combo');
    this.$dimNameEl = document.getElementById('dim-name');
    this.$dimDots = [
      document.getElementById('dot-0'),
      document.getElementById('dot-1'),
      document.getElementById('dot-2'),
    ];
    this.$dashChargesEl = document.getElementById('dash-charges');

    this.$goScore = document.getElementById('go-score');
    this.$goBest = document.getElementById('go-best');
    this.$goBestLabel = document.getElementById('go-best-label');
    this.$newBestBadge = document.getElementById('new-best-badge');
    this.$bestDisplay = document.getElementById('best-score-display');

    this._bindButtons();
  }

  _bindButtons() {
    document.getElementById('btn-start').addEventListener('click', () => {
      this.hideStart();
      this.engine.startGame();
    });

    document.getElementById('btn-play-again').addEventListener('click', () => {
      this.hideGameOver();
      this.engine.startGame();
    });

    document.getElementById('btn-menu').addEventListener('click', () => {
      this.hideGameOver();
      this.showStart();
    });

    document.getElementById('btn-pause-resume').addEventListener('click', () => {
      this.engine.togglePause();
    });

    document.getElementById('btn-pause-menu').addEventListener('click', () => {
      this.engine.state = 'menu';
      this.hidePause();
      this.hideHUD();
      this.showStart();
      this.engine.audio.stopBgMusic();
    });

    document.getElementById('pause-btn').addEventListener('click', () => {
      this.engine.togglePause();
    });

    document.getElementById('btn-mute').addEventListener('click', () => {
      const on = this.engine.audio.toggleMute();
      document.getElementById('btn-mute').textContent = on ? '🔊' : '🔇';
    });
  }

  // ─── Score ───

  updateScore(score) {
    if (this.$scoreEl) this.$scoreEl.textContent = score.toLocaleString();
  }

  updateMultiplier(mult, combo) {
    if (this.$multiplierEl) {
      if (mult > 1) {
        this.$multiplierEl.textContent = `×${mult.toFixed(1)}`;
      } else {
        this.$multiplierEl.textContent = '';
      }
    }
    if (this.$comboEl) {
      this.$comboEl.textContent = combo > 1 ? `${combo} combo` : '';
    }
  }

  updateDimension(dim, name) {
    if (this.$dimNameEl) this.$dimNameEl.textContent = name;
    this.$dimDots.forEach((dot, i) => {
      dot.className = 'dim-dot';
      if (i === dim) dot.classList.add(`active-d${dim}`);
    });

    const colors = ['#ff2d78', '#9d4edd', '#06ffa5'];
    if (this.$scoreEl) this.$scoreEl.style.color = colors[dim];
    if (this.$scoreEl) this.$scoreEl.style.textShadow = `0 0 20px ${colors[dim]}`;
  }

  updateHint(safeDim, currentDim) {
    const bar = document.getElementById('hint-bar');
    const dimEl = document.getElementById('hint-dim');
    if (!bar || !dimEl) return;
    if (safeDim === -1 || safeDim === currentDim) {
      bar.style.opacity = '0';
      return;
    }
    const names = ['CYBER', 'VOID', 'FLUX'];
    const colors = ['#ff2d78', '#9d4edd', '#06ffa5'];
    dimEl.textContent = names[safeDim];
    dimEl.style.color = colors[safeDim];
    bar.style.opacity = '1';
  }

  updateDashCharges(charges, max) {
    if (!this.$dashChargesEl) return;
    this.$dashChargesEl.innerHTML = '';
    for (let i = 0; i < max; i++) {
      const d = document.createElement('div');
      d.className = 'dash-charge' + (i < charges ? ' full' : '');
      this.$dashChargesEl.appendChild(d);
    }
  }

  // ─── Screens ───

  showStart() {
    this.$startScreen.classList.remove('hidden');
    const best = parseInt(localStorage.getItem('vr_best') || '0');
    if (this.$bestDisplay) {
      this.$bestDisplay.innerHTML = `BEST <span>${best.toLocaleString()}</span>`;
    }
  }

  hideStart() {
    this.$startScreen.classList.add('hidden');
  }

  showHUD(maxDashes) {
    this.$hudEl.classList.remove('hidden');
    document.getElementById('pause-btn').classList.remove('hidden');
    this.updateDashCharges(maxDashes, maxDashes);
  }

  hideHUD() {
    this.$hudEl.classList.add('hidden');
    document.getElementById('pause-btn').classList.add('hidden');
  }

  showGameOver(score, best, isNewBest) {
    if (this.$goScore) this.$goScore.textContent = Math.floor(score).toLocaleString();
    if (this.$goBest) {
      this.$goBest.textContent = Math.floor(best).toLocaleString();
      if (isNewBest) {
        this.$goBest.classList.add('new-best');
        if (this.$newBestBadge) this.$newBestBadge.style.display = 'inline-block';
      } else {
        this.$goBest.classList.remove('new-best');
        if (this.$newBestBadge) this.$newBestBadge.style.display = 'none';
      }
    }
    this.$gameoverScreen.classList.remove('hidden');
    this.hideHUD();
  }

  hideGameOver() {
    this.$gameoverScreen.classList.add('hidden');
  }

  showPause() {
    this.$pauseScreen.classList.remove('hidden');
  }

  hidePause() {
    this.$pauseScreen.classList.add('hidden');
  }
}
