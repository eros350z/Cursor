/**
 * Procedural audio engine using Web Audio API.
 * No external sound files needed — everything is synthesized.
 */
export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.masterGain = null;
    this.enabled = true;
    this._bgNodes = [];
    this._bgRunning = false;
    this._bgScheduleId = null;
    this._currentDim = 0;
    this._tempo = 128; // BPM
  }

  async init() {
    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.value = 0.5;
      this.masterGain.connect(this.ctx.destination);
    } catch (e) {
      this.enabled = false;
    }
  }

  resume() {
    if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
  }

  _note(freq, type, start, duration, vol = 0.15, pan = 0) {
    if (!this.enabled || !this.ctx) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    const panner = this.ctx.createStereoPanner();
    panner.pan.value = pan;
    osc.type = type;
    osc.frequency.setValueAtTime(freq, start);
    gain.gain.setValueAtTime(0, start);
    gain.gain.linearRampToValueAtTime(vol, start + 0.01);
    gain.gain.setValueAtTime(vol, start + duration * 0.7);
    gain.gain.linearRampToValueAtTime(0, start + duration);
    osc.connect(gain);
    gain.connect(panner);
    panner.connect(this.masterGain);
    osc.start(start);
    osc.stop(start + duration + 0.05);
    return osc;
  }

  _noise(start, duration, vol = 0.05, highpass = 800) {
    if (!this.enabled || !this.ctx) return;
    const bufSize = this.ctx.sampleRate * 0.5;
    const buf = this.ctx.createBuffer(1, bufSize, this.ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < bufSize; i++) data[i] = Math.random() * 2 - 1;
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'highpass';
    filter.frequency.value = highpass;
    const gain = this.ctx.createGain();
    gain.gain.setValueAtTime(vol, start);
    gain.gain.linearRampToValueAtTime(0, start + duration);
    src.connect(filter);
    filter.connect(gain);
    gain.connect(this.masterGain);
    src.start(start);
    src.stop(start + duration);
  }

  // ─── Sound effects ───

  playJump() {
    if (!this.enabled || !this.ctx) return;
    const t = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(220, t);
    osc.frequency.exponentialRampToValueAtTime(660, t + 0.12);
    gain.gain.setValueAtTime(0.2, t);
    gain.gain.linearRampToValueAtTime(0, t + 0.18);
    osc.connect(gain);
    gain.connect(this.masterGain);
    osc.start(t);
    osc.stop(t + 0.2);
  }

  playDimensionShift(dim) {
    if (!this.enabled || !this.ctx) return;
    const t = this.ctx.currentTime;
    const freqs = [
      [330, 440, 660, 880],
      [277, 370, 554, 740],
      [370, 494, 740, 987],
    ];
    const chosen = freqs[dim % 3];
    chosen.forEach((f, i) => {
      this._note(f, 'sine', t + i * 0.04, 0.3, 0.12, i % 2 === 0 ? -0.3 : 0.3);
    });
    this._noise(t, 0.1, 0.04, 1200);
  }

  playDash() {
    if (!this.enabled || !this.ctx) return;
    const t = this.ctx.currentTime;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(880, t);
    osc.frequency.exponentialRampToValueAtTime(110, t + 0.3);
    gain.gain.setValueAtTime(0.18, t);
    gain.gain.linearRampToValueAtTime(0, t + 0.35);
    osc.connect(gain);
    gain.connect(this.masterGain);
    osc.start(t);
    osc.stop(t + 0.38);
    this._noise(t, 0.15, 0.06, 600);
  }

  playDeath() {
    if (!this.enabled || !this.ctx) return;
    const t = this.ctx.currentTime;
    [220, 185, 155, 110].forEach((f, i) => {
      this._note(f, 'sawtooth', t + i * 0.08, 0.35, 0.14);
    });
    this._noise(t, 0.4, 0.1, 200);
  }

  playScore(combo) {
    if (!this.enabled || !this.ctx) return;
    const t = this.ctx.currentTime;
    const base = 440 * Math.pow(1.06, Math.min(combo, 20));
    this._note(base, 'sine', t, 0.08, 0.1);
  }

  playLand() {
    if (!this.enabled || !this.ctx) return;
    const t = this.ctx.currentTime;
    this._noise(t, 0.06, 0.12, 300);
    this._note(110, 'sine', t, 0.05, 0.08);
  }

  // ─── Background music (minimal procedural) ───

  startBgMusic(dim) {
    this._currentDim = dim;
    if (this._bgRunning) return;
    this._bgRunning = true;
    this._scheduleBeat(this.ctx ? this.ctx.currentTime : 0);
  }

  changeDimMusic(dim) {
    this._currentDim = dim;
  }

  stopBgMusic() {
    this._bgRunning = false;
    if (this._bgScheduleId) clearTimeout(this._bgScheduleId);
  }

  _scheduleBeat(startTime) {
    if (!this._bgRunning || !this.enabled || !this.ctx) return;
    const now = this.ctx.currentTime;
    const beatDur = 60 / this._tempo;
    const lookAhead = 0.3;
    let time = Math.max(startTime, now);

    const patterns = [
      { kick: [0, 2], snare: [1, 3], hihat: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5] },
      { kick: [0, 1.5, 2.5], snare: [1, 3], hihat: [0, 0.75, 1.5, 2.25, 3] },
      { kick: [0, 0.75, 2, 3], snare: [1, 2.5], hihat: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5] },
    ];
    const pat = patterns[this._currentDim % 3];
    const beats = 4;

    const melody = [
      [0, 1, 2, 3].map(b => ({ beat: b, freq: [220, 261, 294, 349][b] })),
      [0, 1, 2, 3].map(b => ({ beat: b, freq: [185, 220, 277, 330][b] })),
      [0, 1, 2, 3].map(b => ({ beat: b, freq: [277, 330, 370, 494][b] })),
    ];

    // kick
    pat.kick.forEach(b => this._kick(time + b * beatDur));
    // snare
    pat.snare.forEach(b => this._snare(time + b * beatDur));
    // hihat
    pat.hihat.forEach(b => this._hihat(time + b * beatDur));
    // melody
    melody[this._currentDim % 3].forEach(m => {
      this._note(m.freq, 'triangle', time + m.beat * beatDur, beatDur * 0.7, 0.04);
    });

    const nextBeat = time + beats * beatDur;
    const delay = Math.max(0, (nextBeat - now - lookAhead) * 1000);
    this._bgScheduleId = setTimeout(() => this._scheduleBeat(nextBeat), delay);
  }

  _kick(t) {
    if (!this.ctx) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'sine';
    osc.frequency.setValueAtTime(150, t);
    osc.frequency.exponentialRampToValueAtTime(40, t + 0.08);
    gain.gain.setValueAtTime(0.35, t);
    gain.gain.linearRampToValueAtTime(0, t + 0.18);
    osc.connect(gain);
    gain.connect(this.masterGain);
    osc.start(t);
    osc.stop(t + 0.2);
  }

  _snare(t) {
    if (!this.ctx) return;
    this._noise(t, 0.12, 0.08, 800);
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();
    osc.type = 'triangle';
    osc.frequency.setValueAtTime(180, t);
    gain.gain.setValueAtTime(0.1, t);
    gain.gain.linearRampToValueAtTime(0, t + 0.1);
    osc.connect(gain);
    gain.connect(this.masterGain);
    osc.start(t);
    osc.stop(t + 0.12);
  }

  _hihat(t) {
    this._noise(t, 0.04, 0.03, 5000);
  }

  setVolume(v) {
    if (this.masterGain) this.masterGain.gain.value = v;
  }

  toggleMute() {
    this.enabled = !this.enabled;
    if (this.masterGain) {
      this.masterGain.gain.value = this.enabled ? 0.5 : 0;
    }
    return this.enabled;
  }
}
