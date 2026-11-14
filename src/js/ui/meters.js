import { state } from '../state/store.js';
import { fitCv } from './timeline.js';


export function rms(ana) {
  if (!ana) return 0;
  ana.getByteTimeDomainData(state.meterBuf);
  let s = 0; for (let i = 0; i < state.meterBuf.length; i++) { const v = (state.meterBuf[i] - 128) / 128; s += v * v; }
  return Math.sqrt(s / state.meterBuf.length);
}


export function drawMeter(cv, lvl, nch) {
  if (!cv) return; fitCv(cv);
  const g = cv.getContext('2d'), W = cv.width, H = cv.height, dpr = window.devicePixelRatio || 1;
  g.clearRect(0, 0, W, H);
  const isLight = document.documentElement.getAttribute('data-theme') === 'light';
  const unlit = isLight ? '#DDD7CD' : '#191c21';
  const amberColor = isLight ? '#4B6227' : '#E9A23B';
  const redColor = isLight ? '#C23B4A' : '#E4604E';
  const segs = 24, segH = H / segs, lit = Math.round(lvl * segs), cw = W / nch - 2 * dpr;
  for (let c = 0; c < nch; c++) for (let i = 0; i < segs; i++) {
    const y = H - (i + 1) * segH;
    g.fillStyle = i < lit ? (i >= segs - 4 ? redColor : amberColor) : unlit;
    g.fillRect(c * (W / nch) + dpr, y + 1 * dpr, cw, segH - 2 * dpr);
  }
}


export function drawAllMeters() {
  for (const s of state.stemKeys) {
    const st = state.STEMS[s];
    const inst = Math.min(1, rms(st.ana) * 3.2);
    st.lvl = Math.max(inst, (st.lvl || 0) * .9);
    drawMeter(state.meterCv[s], st.lvl, 1);
  }
  const mL = Math.min(1, rms(state.anaL) * 3.2), mR = Math.min(1, rms(state.anaR) * 3.2);
  window._mL = Math.max(mL, (window._mL || 0) * .9); window._mR = Math.max(mR, (window._mR || 0) * .9);
  drawMeter(state.meterCv.master, window._mL, 1);
  const cv = state.meterCv.master;
  if (cv && cv.width) {
    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    const unlit = isLight ? '#DDD7CD' : '#191c21';
    const amberColor = isLight ? '#4B6227' : '#E9A23B';
    const redColor = isLight ? '#C23B4A' : '#E4604E';
    const g = cv.getContext('2d'), W = cv.width, H = cv.height, dpr = window.devicePixelRatio || 1;
    const segs = 24, segH = H / segs, lit = Math.round(window._mR * segs), cw = W / 2 - 2 * dpr;
    for (let i = 0; i < segs; i++) {
      const y = H - (i + 1) * segH;
      g.fillStyle = i < lit ? (i >= segs - 4 ? redColor : amberColor) : unlit;
      g.fillRect(W / 2 + dpr, y + 1 * dpr, cw, segH - 2 * dpr);
    }
  }
  drawStageStereoMeter();
}



export function drawStageStereoMeter() {
  const cv = document.getElementById('stageStereoCanvas');
  if (!cv) return;
  const dpr = window.devicePixelRatio || 1;
  const W = cv.clientWidth || 20, H = cv.clientHeight || (window.innerHeight < 550 ? 64 : 220);
  const targetW = Math.floor(W * dpr), targetH = Math.floor(H * dpr);
  if (cv.width !== targetW || cv.height !== targetH) {
    cv.width = targetW; cv.height = targetH;
  }
  const g = cv.getContext('2d');
  g.clearRect(0, 0, targetW, targetH);

  const isLight = document.documentElement.getAttribute('data-theme') === 'light';
  const unlit = isLight ? '#DDD7CD' : '#12151b';
  const greenColor = isLight ? '#1F8A55' : '#43B97C';
  const amberColor = isLight ? '#4B6227' : '#E9A23B';
  const redColor = isLight ? '#C23B4A' : '#E4604E';

  const segs = 28;
  const segH = targetH / segs;
  const gapBetween = Math.floor(3 * dpr);
  const colW = Math.floor((targetW - gapBetween) / 2);

  const isMuted = state.STEMS.master.muted;
  const rawL = isMuted ? 0 : (window._mL || 0);
  const rawR = isMuted ? 0 : (window._mR || 0);
  const litL = Math.round(rawL * segs);
  const litR = Math.round(rawR * segs);

  for (let i = 0; i < segs; i++) {
    const y = targetH - (i + 1) * segH;
    const isClip = i >= segs - 2;
    const isAmber = i >= segs - 8;

    // Canal L (línea izquierda)
    const colorL = isClip ? redColor : (isAmber ? amberColor : greenColor);
    g.fillStyle = i < litL ? colorL : unlit;
    g.fillRect(0, y + dpr, colW, segH - 2 * dpr);

    // Canal R (línea derecha)
    const colorR = isClip ? redColor : (isAmber ? amberColor : greenColor);
    g.fillStyle = i < litR ? colorR : unlit;
    g.fillRect(colW + gapBetween, y + dpr, colW, segH - 2 * dpr);
  }
}

export function initializeMeters() {


/* ---------- Medidores LED de 24 Segmentos ---------- */
state.meterBuf = new Uint8Array(512);
}

