// Synth sound effects with WebAudio. No audio files.
import { store } from './platform';

let AC: AudioContext | null = null;
let muted: boolean = store.get('muted', false);
let noiseBuf: AudioBuffer | null = null;

export const isMuted = () => muted;
export function setMuted(v: boolean) { muted = v; store.set('muted', v); }

/** Must be called from a user gesture at least once (iOS unlocks audio on touch). */
export function audio() {
  if (!AC) { try { AC = new (window.AudioContext || (window as any).webkitAudioContext)(); } catch { /* no audio */ } }
  if (AC && AC.state === 'suspended') AC.resume();
}

function tone(f: number, d: number, type: OscillatorType = 'square', vol = 0.05, slide = 1, delay = 0) {
  if (!AC || muted) return; const t = AC.currentTime + delay;
  const o = AC.createOscillator(), g = AC.createGain(); o.type = type; o.frequency.setValueAtTime(f, t);
  if (slide !== 1) o.frequency.exponentialRampToValueAtTime(Math.max(20, f * slide), t + d);
  g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
  o.connect(g).connect(AC.destination); o.start(t); o.stop(t + d + 0.02);
}
function noise(d: number, vol = 0.12, freq = 1200, delay = 0) {
  if (!AC || muted) return; const t = AC.currentTime + delay;
  if (!noiseBuf) {
    noiseBuf = AC.createBuffer(1, AC.sampleRate * 0.6, AC.sampleRate);
    const ch = noiseBuf.getChannelData(0); for (let i = 0; i < ch.length; i++) ch[i] = Math.random() * 2 - 1;
  }
  const s = AC.createBufferSource(); s.buffer = noiseBuf;
  const f = AC.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = freq; f.Q.value = 0.8;
  const g = AC.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + d);
  s.connect(f).connect(g).connect(AC.destination); s.start(t); s.stop(t + d + 0.02);
}

export const SFX = {
  card: () => tone(520, 0.07, 'triangle', 0.05, 1.8),
  deny: () => tone(160, 0.12, 'square', 0.04, 0.8),
  hit: (el?: string) => { noise(0.14, 0.16, el === 'tide' ? 700 : el === 'volt' ? 3000 : 1400); tone(150, 0.12, 'square', 0.05, 0.5); },
  crit: () => { noise(0.25, 0.2, 900); tone(90, 0.3, 'sawtooth', 0.07, 0.4); tone(880, 0.12, 'triangle', 0.04, 1.5, 0.02); },
  ouch: () => { noise(0.18, 0.18, 500); tone(110, 0.2, 'square', 0.06, 0.6); },
  heal: () => [523, 659, 784].forEach((f, i) => tone(f, 0.16, 'sine', 0.05, 1, i * 0.06)),
  shield: () => tone(330, 0.2, 'triangle', 0.05, 1.6),
  zap: () => { noise(0.08, 0.12, 4000); tone(1200, 0.06, 'sawtooth', 0.03, 0.4); },
  throw: () => tone(300, 0.3, 'triangle', 0.05, 2.5),
  tick: () => tone(900, 0.05, 'square', 0.04),
  caught: () => [523, 659, 784, 1046].forEach((f, i) => tone(f, 0.22, 'triangle', 0.06, 1, i * 0.09)),
  broke: () => { noise(0.3, 0.2, 2000); tone(220, 0.3, 'sawtooth', 0.05, 0.5); },
  ko: () => { tone(400, 0.6, 'sawtooth', 0.06, 0.15); noise(0.5, 0.15, 600); },
  win: () => [392, 523, 659, 784, 1046].forEach((f, i) => tone(f, 0.25, 'triangle', 0.05, 1, i * 0.08)),
  lose: () => [392, 330, 262, 196].forEach((f, i) => tone(f, 0.35, 'triangle', 0.05, 1, i * 0.16)),
  swap: () => tone(250, 0.25, 'sine', 0.06, 3),
  stomp: () => { noise(0.3, 0.2, 300); tone(70, 0.3, 'sine', 0.12, 0.5); },
  pick: () => { tone(660, 0.08, 'triangle', 0.05, 1.3); tone(990, 0.1, 'triangle', 0.04, 1, 0.06); },
  energy: () => tone(700, 0.15, 'triangle', 0.05, 2),
  focus: () => tone(500, 0.2, 'sine', 0.05, 2),
};
