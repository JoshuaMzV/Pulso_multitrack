import { state } from '../state/store.js';
import { isTransposeExcludedStem } from './stems.js';
import { applyMix } from './transport.js';
import { clearEqRoutes, registerEqRoute, restoreEq } from './eq.js';



export function orderMixerStemKeys(keys) {
  const getPriority = key => {
    const stem = state.STEMS[key] || {};
    const id = String(key).toLowerCase();
    const label = String(stem.label || '').toLowerCase();
    const type = String(stem.type || '').toLowerCase();
    if (id === 'click' || type === 'click' || /click|metr[oó]n/.test(`${id} ${label}`)) return 0;
    if (id === 'guide' || type === 'guide' || /gu[ií]a|guide/.test(`${id} ${label}`)) return 1;
    return 2;
  };
  return [...new Set(keys || [])].sort((a, b) => {
    return getPriority(a) - getPriority(b);
  });
}


export function isMixerPriorityCue(key) {
  const stem = state.STEMS[key] || {};
  const identity = `${key} ${stem.label || ''} ${stem.type || ''}`.toLowerCase();
  return /click|metr[oó]n|gu[ií]a|guide/.test(identity);
}



export function getAudioCtx() {
  if (!state.ctx || !state.masterG) initAudio();
  return state.ctx;
}


export function getAudioDecoderContext() {
  const OfflineContext = window.OfflineAudioContext || window.webkitOfflineAudioContext;
  if (!OfflineContext) return getAudioCtx();
  if (!state.decodeCtx) state.decodeCtx = new OfflineContext(1, 1, 44100);
  return state.decodeCtx;
}



export function ensureStemAudioNode(s) {
  if (!state.ctx || s === 'master' || !state.STEMS[s]) return;
  if (!state.masterG) initAudio();
  const dest = s === 'talkback' ? state.ctx.destination
    : isMixerPriorityCue(s) ? state.cueOutput : state.masterG;
  if (state.STEMS[s].node && state.STEMS[s].destination !== dest) {
    state.STEMS[s].ana.disconnect();
    delete state.STEMS[s].node;
    delete state.STEMS[s].transposeDelay;
  }
  if (!state.STEMS[s].node) {
    const g = state.ctx.createGain(), ana = state.ctx.createAnalyser();
    ana.fftSize = 512;
    const outputDelay = isTransposeExcludedStem(s) ? state.ctx.createDelay(1) : null;
    if (outputDelay) {
      g.connect(outputDelay);
      outputDelay.connect(ana);
      state.STEMS[s].transposeDelay = outputDelay;
    } else {
      g.connect(ana);
    }
    ana.connect(dest);
    const input = state.ctx.createGain();
    if (isMixerPriorityCue(s)) input.connect(g);
    else registerEqRoute(s, input, g);
    state.STEMS[s].node = input;
    state.STEMS[s].faderNode = g;
    restoreEq(s);
    state.STEMS[s].ana = ana;
    state.STEMS[s].destination = dest;
    state.STEMS[s].lvl = 0;
    const now = state.ctx.currentTime;
    g.gain.setValueAtTime(state.STEMS[s].muted ? 0 : state.STEMS[s].gain, now);
  }
}



export function initAudio() {
  if (state.ctx && state.masterG) return state.ctx;
  if (!state.ctx) {
    state.ctx = new (window.AudioContext || window.webkitAudioContext)();
  }
  state.masterG = state.ctx.createGain(); state.kill = state.ctx.createGain();
  const masterOutput = state.masterOutput = state.ctx.createGain();
  state.musicOutput = state.ctx.createGain();
  state.cueOutput = state.ctx.createGain();
  state.cueOutput.connect(state.ctx.destination);
  const split = state.ctx.createChannelSplitter(2);
  state.anaL = state.ctx.createAnalyser(); state.anaR = state.ctx.createAnalyser();
  [state.anaL, state.anaR].forEach(a => a.fftSize = 512);
  state.masterG.connect(state.kill); registerEqRoute('master', state.kill, masterOutput);
  restoreEq('master');
  masterOutput.connect(state.musicOutput); state.musicOutput.connect(state.ctx.destination);
  masterOutput.connect(split);
  split.connect(state.anaL, 0); split.connect(state.anaR, 1);
  for (const s of Object.keys(state.STEMS)) {
    if (s !== 'master') ensureStemAudioNode(s);
  }
  state.STEMS.master.node = state.masterG;
  // Delay para voz guía (pre-fader espacial)
  state.delayNode = state.ctx.createDelay(1); state.delayNode.delayTime.value = .34;
  state.delayFB = state.ctx.createGain(); state.delayFB.gain.value = 0;
  state.leadSend = state.ctx.createGain(); state.leadSend.gain.value = .35;
  const wet = state.ctx.createGain(); wet.gain.value = .4;
  state.leadSend.connect(state.delayNode); state.delayNode.connect(wet);
  if (state.STEMS.lead && state.STEMS.lead.node) wet.connect(state.STEMS.lead.node);
  state.delayNode.connect(state.delayFB); state.delayFB.connect(state.delayNode);
  // Buffer de ruido para batería (snare y hi-hat)
  state.noiseBuf = state.ctx.createBuffer(1, state.ctx.sampleRate * .5, state.ctx.sampleRate);
  const d = state.noiseBuf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  applyMix();
  return state.ctx;
}

// La cola conserva los filtros, faders y transposición de la canción saliente.
export function detachMixForTail(at, end) {
  const { musicOutput, cueOutput, delayNode, delayFB, leadSend } = state;
  if (end > at) {
    musicOutput.gain.setValueAtTime(1, at);
    musicOutput.gain.linearRampToValueAtTime(0, end);
  } else musicOutput.gain.setValueAtTime(0, at);
  cueOutput.gain.setValueAtTime(0, at);
  const sources = [...state.activeNodes];
  const splitters = state.REAL_STEM_SOURCE_SPLITTERS;
  const stretchRoutes = state.REAL_STRETCH_ROUTES;
  const padGain = state.padGain;
  state.activeNodes = new Set();
  state.REAL_STEM_SOURCES = {};
  state.REAL_STEM_SOURCE_SPLITTERS = [];
  state.REAL_STRETCH_ROUTES = [];
  state.REAL_STRETCH_ROUTE_SONG = null;
  clearEqRoutes();
  for (const channel of Object.values(state.STEMS)) {
    for (const key of ['node', 'faderNode', 'ana', 'transposeDelay', 'destination']) delete channel[key];
  }
  state.masterG = null;
  initAudio();
  if (padGain) {
    padGain.disconnect();
    padGain.connect(state.masterG);
  }
  return () => {
    for (const source of sources) {
      try { source.stop(); } catch (_) {}
      source.disconnect();
    }
    for (const route of stretchRoutes) {
      [route.inputMerger, route.stretch, route.outputSplitter, ...route.outputMergers]
        .forEach(node => node.disconnect());
    }
    [musicOutput, cueOutput, delayNode, delayFB, leadSend, ...splitters]
      .forEach(node => node?.disconnect());
  };
}



export function vKick(t, v) {
  const o = state.ctx.createOscillator(), g = state.ctx.createGain();
  o.type = 'sine';
  o.frequency.setValueAtTime(165, t); o.frequency.exponentialRampToValueAtTime(44, t + .11);
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(v, t + .004); g.gain.exponentialRampToValueAtTime(.0001, t + .3);
  o.connect(g); g.connect(state.STEMS.drums.node); o.start(t); o.stop(t + .32); state.addNode(o);
}


export function vHat(t, v, dec) {
  const s = state.ctx.createBufferSource(); s.buffer = state.noiseBuf; s.playbackRate.value = 1.4;
  const f = state.ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 7200;
  const g = state.ctx.createGain();
  g.gain.setValueAtTime(v, t); g.gain.exponentialRampToValueAtTime(.0001, t + dec);
  s.connect(f); f.connect(g); g.connect(state.STEMS.drums.node); s.start(t); s.stop(t + dec + .02); state.addNode(s);
}


export function vSnare(t, v) {
  const s = state.ctx.createBufferSource(); s.buffer = state.noiseBuf;
  const f = state.ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = 1900; f.Q.value = .8;
  const g = state.ctx.createGain();
  g.gain.setValueAtTime(v, t); g.gain.exponentialRampToValueAtTime(.0001, t + .16);
  s.connect(f); f.connect(g); g.connect(state.STEMS.drums.node); s.start(t); s.stop(t + .2); state.addNode(s);
  const o = state.ctx.createOscillator(), g2 = state.ctx.createGain();
  o.type = 'triangle'; o.frequency.value = 185;
  g2.gain.setValueAtTime(v * .5, t); g2.gain.exponentialRampToValueAtTime(.0001, t + .08);
  o.connect(g2); g2.connect(state.STEMS.drums.node); o.start(t); o.stop(t + .1); state.addNode(o);
}


export function vBass(t, f, dur, v) {
  f *= state.getTransposeFrequencyFactor();
  const o = state.ctx.createOscillator(), g = state.ctx.createGain(), fl = state.ctx.createBiquadFilter();
  o.type = 'sawtooth'; o.frequency.value = f;
  fl.type = 'lowpass'; fl.Q.value = 1.2;
  fl.frequency.setValueAtTime(900, t); fl.frequency.exponentialRampToValueAtTime(220, t + Math.min(.3, dur));
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(v, t + .02);
  g.gain.setValueAtTime(v, t + dur * .55); g.gain.exponentialRampToValueAtTime(.0001, t + dur);
  o.connect(g); g.connect(fl); fl.connect(state.STEMS.bass.node); o.start(t); o.stop(t + dur + .05); state.addNode(o);
}


export function vPad(t, notes, dur, v) {
  notes.map(f => f * state.getTransposeFrequencyFactor()).forEach(f => {
    [-6, 6].forEach(det => {
      const o = state.ctx.createOscillator(), g = state.ctx.createGain(), fl = state.ctx.createBiquadFilter();
      o.type = 'sawtooth'; o.frequency.value = f; o.detune.value = det;
      fl.type = 'lowpass'; fl.frequency.value = 780; fl.Q.value = .6;
      g.gain.setValueAtTime(.0001, t); g.gain.linearRampToValueAtTime(v, t + .35);
      g.gain.setValueAtTime(v, t + dur * .7); g.gain.linearRampToValueAtTime(.0001, t + dur + .3);
      o.connect(g); g.connect(fl); fl.connect(state.STEMS.keys.node); o.start(t); o.stop(t + dur + .4); state.addNode(o);
    });
  });
}


export function vLead(t, f, dur, v) {
  const o = state.ctx.createOscillator(), g = state.ctx.createGain();
  o.type = 'triangle'; o.frequency.value = f;
  const lfo = state.ctx.createOscillator(), lg = state.ctx.createGain();
  lfo.frequency.value = 5.2; lg.gain.value = f * .006; lfo.connect(lg); lg.connect(o.frequency);
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(v, t + .02);
  g.gain.setValueAtTime(v * .75, t + dur * .8); g.gain.exponentialRampToValueAtTime(.0001, t + dur + .12);
  o.connect(g); g.connect(state.STEMS.lead.node); g.connect(state.leadSend);
  o.start(t); o.stop(t + dur + .2); lfo.start(t); lfo.stop(t + dur + .2); state.addNode(o); state.addNode(lfo);
}


export function vClick(t, acc) {
  const o = state.ctx.createOscillator(), g = state.ctx.createGain(), f = state.ctx.createBiquadFilter();
  o.type = 'square'; o.frequency.value = acc ? 1660 : 1100;
  f.type = 'highpass'; f.frequency.value = 800;
  g.gain.setValueAtTime(.18, t); g.gain.exponentialRampToValueAtTime(.0001, t + .035);
  o.connect(f); f.connect(g); g.connect(state.STEMS.click.node); o.start(t); o.stop(t + .05); state.addNode(o);
}


/* Helpers de síntesis para los stems dinámicos adicionales */

export function vHatTo(t, v, dec, targetNode) {
  if (!state.ctx || !targetNode) return;
  const s = state.ctx.createBufferSource(); s.buffer = state.noiseBuf; s.playbackRate.value = 1.3;
  const f = state.ctx.createBiquadFilter(); f.type = 'highpass'; f.frequency.value = 6500;
  const g = state.ctx.createGain();
  g.gain.setValueAtTime(v, t); g.gain.exponentialRampToValueAtTime(.0001, t + dec);
  s.connect(f); f.connect(g); g.connect(targetNode); s.start(t); s.stop(t + dec + .02); state.addNode(s);
}


export function vPadTo(t, notes, dur, v, targetNode) {
  if (!state.ctx || !targetNode) return;
  notes.map(f => f * state.getTransposeFrequencyFactor()).forEach(f => {
    const o = state.ctx.createOscillator(), g = state.ctx.createGain(), fl = state.ctx.createBiquadFilter();
    o.type = 'sawtooth'; o.frequency.value = f;
    fl.type = 'lowpass'; fl.frequency.value = 820; fl.Q.value = .7;
    g.gain.setValueAtTime(.0001, t); g.gain.linearRampToValueAtTime(v, t + .25);
    g.gain.setValueAtTime(v, t + dur * .7); g.gain.linearRampToValueAtTime(.0001, t + dur + .2);
    o.connect(g); g.connect(fl); fl.connect(targetNode); o.start(t); o.stop(t + dur + .3); state.addNode(o);
  });
}


export function vLeadTo(t, f, dur, v, targetNode) {
  if (!state.ctx || !targetNode) return;
  f *= state.getTransposeFrequencyFactor();
  const o = state.ctx.createOscillator(), g = state.ctx.createGain();
  o.type = 'triangle'; o.frequency.value = f;
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(v, t + .02);
  g.gain.setValueAtTime(v * .7, t + dur * .8); g.gain.exponentialRampToValueAtTime(.0001, t + dur + .1);
  o.connect(g); g.connect(targetNode); o.start(t); o.stop(t + dur + .15); state.addNode(o);
}


export function vSubBass(t, f, dur, v) {
  if (!state.ctx || !state.STEMS.sub_bass?.node) return;
  f *= state.getTransposeFrequencyFactor();
  const o = state.ctx.createOscillator(), g = state.ctx.createGain();
  o.type = 'sine'; o.frequency.value = f;
  g.gain.setValueAtTime(.0001, t); g.gain.exponentialRampToValueAtTime(v, t + .03);
  g.gain.setValueAtTime(v, t + dur * .6); g.gain.exponentialRampToValueAtTime(.0001, t + dur);
  o.connect(g); g.connect(state.STEMS.sub_bass.node); o.start(t); o.stop(t + dur + .05); state.addNode(o);
}

export function initializeAudio() {

state.stemKeys = orderMixerStemKeys(state.stemKeys);


/* ---------- Estado del Motor de Audio ---------- */
state.ctx = null;
state.masterG = null;
state.kill = null;
state.anaL = null;
state.anaR = null;
state.noiseBuf = null;

state.delayNode = null;
state.delayFB = null;
state.leadSend = null;

state.isPlaying = false;
state.started = false;
state.pausedBeat = 0;

state.countOn = false;

state.anchor = { t16: 0, time: 0 };
state.current16th = 0;
state.next16thTime = 0;
state.timer = null;

state.activeNodes = new Set();

state.addNode = n => { state.activeNodes.add(n); n.onended = () => state.activeNodes.delete(n); };


state.decodeCtx = null;


state.stepSec = () => 60 / state.bpm / 4;

state.getTransposeFrequencyFactor = () => Math.pow(2, state.transposeSemitones / 12);
}

