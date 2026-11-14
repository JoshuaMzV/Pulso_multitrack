import { gainToDb, dbToGain, positionToGain } from '../audio/levels.js';
import { state } from '../state/store.js';
import { applyMix, syncChannels, jumpTo, getCurrentSectionInfo, getBeat16, togglePlay, stopAll, setBpm } from '../audio/transport.js';
import { say } from './show.js';


// Fader Master y Medidor Estéreo en Vista Show (Sonido Separado L/R)

export function bindStageMaster() {
  const track = document.getElementById('stageMasterTrack');
  const fader = document.getElementById('stageMasterFader');
  if (!track || !fader) return;

  function updateFromPointer(clientY) {
    const rect = track.getBoundingClientRect();
    const capH = fader.offsetHeight || (window.innerHeight < 550 ? 16 : 40);
    const travel = Math.max(1, rect.height - capH);
    // Posicionar el centro del fader cap exactamente en el punto del cursor
    const ratio = state.clamp((rect.bottom - (capH / 2) - clientY) / travel, 0, 1);
    const val = positionToGain(ratio);
    state.STEMS.master.gain = val;
    applyMix();
    syncChannels();
    say('MASTER SALA: ' + state.fmtDb(val));
  }

  let isDragging = false;
  track.addEventListener('pointerdown', e => {
    e.preventDefault();
    isDragging = true;
    track.setPointerCapture(e.pointerId);
    updateFromPointer(e.clientY);
  });
  track.addEventListener('pointermove', e => {
    if (isDragging) {
      e.preventDefault();
      updateFromPointer(e.clientY);
    }
  });
  const stopDrag = e => {
    if (isDragging) {
      isDragging = false;
      try { track.releasePointerCapture(e.pointerId); } catch (_) {}
    }
  };
  track.addEventListener('pointerup', stopDrag);
  track.addEventListener('pointercancel', stopDrag);

  // Ajuste fino con rueda del ratón
  track.addEventListener('wheel', e => {
    e.preventDefault();
    const delta = e.deltaY < 0 ? 1 : -1;
    state.STEMS.master.gain = dbToGain(gainToDb(state.STEMS.master.gain) + delta);
    applyMix();
    syncChannels();
    say('MASTER SALA: ' + state.fmtDb(state.STEMS.master.gain));
  }, { passive: false });

  // Doble clic para volver a 0.0 dB (Unidad)
  track.addEventListener('dblclick', () => {
    state.STEMS.master.gain = 1; // 0 dB: ganancia unitaria
    state.STEMS.master.muted = false;
    applyMix();
    syncChannels();
    say('MASTER: 0.0 dB (UNIDAD)');
  });

  // Botón Mute Master
  const muteBtn = document.getElementById('stageMasterMuteBtn');
  if (muteBtn) {
    muteBtn.addEventListener('click', () => {
      state.STEMS.master.muted = !state.STEMS.master.muted;
      applyMix();
      syncChannels();
      say(state.STEMS.master.muted ? 'MASTER MUTED (SILENCIADO)' : 'MASTER ACTIVO');
    });
  }

  // Botón Unity 0 dB
  const unityBtn = document.getElementById('stageMasterUnityBtn');
  if (unityBtn) {
    unityBtn.addEventListener('click', () => {
      state.STEMS.master.gain = 1; // 0 dB: ganancia unitaria
      state.STEMS.master.muted = false;
      applyMix();
      syncChannels();
      say('MASTER: 0.0 dB (UNIDAD)');
    });
  }

  // Botón -6 dB
  const minusBtn = document.getElementById('stageMasterMinusBtn');
  if (minusBtn) {
    minusBtn.addEventListener('click', () => {
      state.STEMS.master.gain = dbToGain(-6);
      applyMix();
      syncChannels();
      say('MASTER: -6.0 dB');
    });
  }
}


/* ---------- Controlador de Secciones en Vivo (Vista Show) ---------- */

export function getShortSectionCode(name) {
  const n = (name || '').toUpperCase().trim();
  if (n.startsWith('IN')) return 'I';
  if (n.includes('PRE')) return 'PC';
  if (n.startsWith('VERS') || n.startsWith('VER')) {
    const num = n.match(/\d+/);
    return num ? `V${num[0]}` : 'V1';
  }
  if (n.startsWith('COR') || n.startsWith('CHOR')) {
    const num = n.match(/\d+/);
    return num ? `C${num[0]}` : 'C';
  }
  if (n.startsWith('PUEN') || n.startsWith('BRID')) {
    const num = n.match(/\d+/);
    return num ? `P${num[0]}` : 'P';
  }
  if (n.startsWith('OUT') || n.startsWith('FIN')) return 'O';
  if (n.startsWith('SOLO') || n.startsWith('INST')) return 'S';
  return n.slice(0, 2);
}



export function renderSectionMarkers() {
  const container = document.getElementById('heroSectionMarkers');
  if (!container || !state.SONG || !state.SONG.sections) return;
  container.innerHTML = state.SONG.sections.map((s, idx) => {
    const totBars = Math.ceil((state.SONG.total16ths || 128) / 16);
    const leftPct = (s.bar / totBars) * 100;
    const shortCode = getShortSectionCode(s.name);
    const isLocked = (state.loopSectionIdx === idx);
    return `
      <div class="hsm-marker ${isLocked ? 'has-lock' : ''}" data-b16="${s.bar * 16}" data-sec-idx="${idx}" style="left: ${leftPct}%;">
        <div class="hsm-stem-line top"></div>
        <button type="button" class="hsm-loop-lock ${isLocked ? 'locked' : ''}" data-sec-idx="${idx}" title="${isLocked ? 'Desactivar bucle de ' + s.name : 'Repetir ' + s.name + ' en bucle continuo (candado)'}">
          <i data-lucide="${isLocked ? 'lock' : 'repeat'}"></i>
        </button>
        <div class="hsm-stem-line bot"></div>
        <button type="button" class="hsm-circle" data-b16="${s.bar * 16}" data-sec-idx="${idx}" title="Saltar a ${s.name} (${shortCode}) · Compás ${s.bar + 1}">
          <div class="hsm-spinner"></div>
          <div class="hsm-inner">
            <span class="hsm-code">${shortCode}</span>
          </div>
        </button>
      </div>
    `;
  }).join('');

  container.querySelectorAll('.hsm-loop-lock').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const secIdx = +btn.dataset.secIdx;
      toggleSectionLoopFor(secIdx);
    });
  });

  container.querySelectorAll('.hsm-circle').forEach(circle => {
    circle.addEventListener('click', (e) => {
      e.stopPropagation();
      const b16 = +circle.dataset.b16;
      const idx = +circle.dataset.secIdx;
      jumpTo(b16);
      say(`${state.SONG.sections[idx].name}` + (state.loopSectionIdx === idx ? ' (LOOP ACTIVO)' : ''));
    });
  });

  if (window.lucide) lucide.createIcons();
}



export function toggleSectionLoopFor(secIdx) {
  if (state.loopSectionIdx === secIdx) {
    state.loopSectionIdx = -1;
    state.isSectionLooping = false;
    say(`LOOP CANDADO: DESACTIVADO (${state.SONG.sections[secIdx].name})`);
  } else {
    state.loopSectionIdx = secIdx;
    state.isSectionLooping = true;
    const curInfo = getCurrentSectionInfo(getBeat16());
    if (curInfo.idx !== secIdx) {
      jumpTo(state.SONG.sections[secIdx].bar * 16);
    }
    say(`LOOP CANDADO: BLOQUEADO EN ${state.SONG.sections[secIdx].name}`);
  }
  updateSectionLoopUI();
}



export function updateSectionLoopUI() {
  const container = document.getElementById('heroSectionMarkers');
  if (!container) return;
  container.querySelectorAll('.hsm-marker').forEach((marker, idx) => {
    const isLocked = (state.loopSectionIdx === idx);
    const lockBtn = marker.querySelector('.hsm-loop-lock');
    if (lockBtn) {
      lockBtn.classList.toggle('locked', isLocked);
      lockBtn.innerHTML = `<i data-lucide="${isLocked ? 'lock' : 'repeat'}"></i>`;
      lockBtn.title = isLocked ? `Desactivar repetición de ${state.SONG.sections[idx]?.name || ''}` : `Repetir ${state.SONG.sections[idx]?.name || ''} en bucle continuo`;
    }
  });
  if (window.lucide) lucide.createIcons();
}



export function toggleSectionLoop() {
  const info = getCurrentSectionInfo(getBeat16());
  toggleSectionLoopFor(info.idx);
}



export function renderStageSections() {
  renderSectionMarkers();
}

export function initializeControls() {


/* ==========================================================================
   EVENTOS & WIRING DE CONTROLES
   ========================================================================== */
// Transporte en cabecera
state.hdrPlay = document.getElementById('headerPlayBtn');

if (state.hdrPlay) state.hdrPlay.addEventListener('click', togglePlay);

state.hdrStop = document.getElementById('headerStopBtn');

if (state.hdrStop) state.hdrStop.addEventListener('click', stopAll);


// Transporte en Consola
state.cPlay = state.$('#playBtn');

if (state.cPlay) state.cPlay.addEventListener('click', togglePlay);

state.cStop = state.$('#stopBtn');

if (state.cStop) state.cStop.addEventListener('click', stopAll);

bindStageMaster();

state.bindPadWheel();


// Clic en cualquier punto del timeline para saltar inmediatamente
state.tlHit = state.$('#tlHit');

if (state.tlHit) {
  state.tlHit.addEventListener('click', e => {
    const tot16 = state.SONG && state.SONG.total16ths ? state.SONG.total16ths : 128;
    const r = e.currentTarget.getBoundingClientRect();
    jumpTo(Math.round((e.clientX - r.left) / r.width * tot16 / 4) * 4);
  });
  state.tlHit.addEventListener('wheel', e => {
    const tracks = state.$('#tlTracks');
    if (tracks) tracks.scrollTop += e.deltaY;
  }, { passive: true });
}



// Pads de sección en consola
document.querySelectorAll('#editionSecPads .pad').forEach(p => {
  p.addEventListener('click', () => jumpTo(+p.dataset.b16));
});


// Controles de Tempo en Consola
state.bpmDown = state.$('#bpmDown');

if (state.bpmDown) state.bpmDown.addEventListener('click', () => setBpm(state.bpm - 1));

state.bpmUp = state.$('#bpmUp');

if (state.bpmUp) state.bpmUp.addEventListener('click', () => setBpm(state.bpm + 1));


state.bpmDrag = null;

state.bpmDisp = state.$('#bpmDisp');

if (state.bpmDisp) {
  state.bpmDisp.addEventListener('pointerdown', e => {
    state.bpmDrag = { x: e.clientX, b: state.bpm };
    state.bpmDisp.setPointerCapture(e.pointerId);
  });
  state.bpmDisp.addEventListener('pointermove', e => {
    if (state.bpmDrag) setBpm(state.bpmDrag.b + (e.clientX - state.bpmDrag.x) * .12, true);
  });
  state.bpmDisp.addEventListener('pointerup', () => {
    state.bpmDrag = null;
    say('TEMPO ' + state.bpm.toFixed(1) + ' BPM');
  });
}


// TAP Tempo
state.taps = [];

state.tapBtn = state.$('#tapBtn');

if (state.tapBtn) {
  state.tapBtn.addEventListener('click', () => {
    const t = performance.now();
    if (state.taps.length && t - state.taps[state.taps.length - 1] > 2000) state.taps = [];
    state.taps.push(t); state.taps = state.taps.slice(-5);
    if (state.taps.length >= 2) {
      let iv = 0; for (let i = 1; i < state.taps.length; i++) iv += state.taps[i] - state.taps[i - 1];
      setBpm(60000 / (iv / (state.taps.length - 1)));
    } else say('TAP — SIGUE MARCANDO');
  });
}


// Cue: Click y Count-In
state.clickTgl = state.$('#clickTgl');

if (state.clickTgl) {
  state.clickTgl.addEventListener('click', () => {
    const st = state.STEMS.click; st.muted = !st.muted;
    state.clickTgl.classList.toggle('on', !st.muted);
    const bm = document.querySelector(`.chbtn.bm[data-stem="click"]`);
    if (bm) bm.classList.toggle('on', st.muted);
    applyMix(); say('CLICK ' + (st.muted ? 'OFF' : 'ON'));
  });
}


state.countTgl = state.$('#countTgl');

if (state.countTgl) {
  state.countTgl.addEventListener('click', () => {
    state.countOn = !state.countOn;
    state.countTgl.classList.toggle('on', state.countOn);
    say('COUNT-IN ' + (state.countOn ? 'ON — 1 COMPÁS' : 'OFF'));
  });
}


// Macros
document.querySelectorAll('.chip').forEach(ch => {
  ch.addEventListener('click', () => {
    const p = ch.dataset.preset;
    if (p === 'guia') {
      state.STEMS.lead.muted = !state.STEMS.lead.muted;
      ch.classList.toggle('on', state.STEMS.lead.muted);
      say(state.STEMS.lead.muted ? 'MACRO: GUÍA SILENCIADA' : 'MACRO: GUÍA ACTIVA');
    } else if (p === 'soloClick') {
      const musicStems = state.stemKeys.filter(s => s !== 'click' && s !== 'talkback');
      const all = musicStems.every(s => state.STEMS[s].muted);
      musicStems.forEach(s => state.STEMS[s].muted = !all);
      ch.classList.toggle('on', !all);
      say(!all ? 'MACRO: SOLO CLICK (ENSAYO)' : 'MACRO: BANDA COMPLETA');
    } else {
      Object.values(state.STEMS).forEach(st => { st.gain = st.def; st.muted = false; st.solo = false; });
      document.querySelectorAll('.chip').forEach(c => { if (c.dataset.preset !== 'reset') c.classList.remove('on'); });
      if (state.clickTgl) state.clickTgl.classList.add('on');
      say('MACRO: MEZCLA RESTABLECIDA');
    }
    syncChannels(); applyMix();
  });
});


// Tecla Espacio para Play / Pause global
window.addEventListener('keydown', e => {
  if (e.code !== 'Space' || e.target.closest('button,input,a,textarea,select,[role="slider"]')) return;
  e.preventDefault(); togglePlay();
});
}

