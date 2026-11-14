import { dbToGain, gainToDb, gainToPosition } from './levels.js';
import { state } from '../state/store.js';
import { scheduleStep, stopRealStems, setTransposeCompensationDelay, loadRealStems, ensureRealStretchRoutes, playRealStems, getCachedSongAudio, hasRealSongAudio, preloadSongAudio } from './stems.js';
import { say, updateTransport, syncModernUI, drawHeroWaveform } from '../ui/show.js';
import { detachMixForTail, initAudio, ensureStemAudioNode, isMixerPriorityCue } from './engine.js';
import { selectSong, getSongTransition } from '../ui/setlists.js';

let queuedSection = null;
let outgoingAnchor = null;
let playbackRevision = 0;
let tail = null;
let missedOverlap = null;
let preloadedNext = null;

function clearTail() {
  if (!tail) return;
  clearTimeout(tail.timer);
  tail.dispose();
  tail = null;
}

function advanceAtSongEnd() {
  if (!state.isPlaying || state.isSectionLooping || queuedSection) return false;
  const song = state.SONG;
  const nextIndex = state.currentSongIdx + 1;
  const next = state.SONGS_DATA[nextIndex];
  if (next !== preloadedNext) {
    preloadedNext = next;
    preloadSongAudio(next);
  }
  if (missedOverlap && missedOverlap.next !== next) missedOverlap = null;
  const mode = getSongTransition(song);
  const duration = getCachedSongAudio(song)?.maxDuration ||
    (song.total16ths || 128) * state.stepSec();
  const end = state.anchor.time - state.anchor.t16 * state.stepSec() +
    duration + (state.REAL_STRETCH_LATENCY || 0);
  const overlap = next && mode === 'overlap' && duration > 8;
  const at = overlap ? end - 8 : end;
  const now = state.ctx.currentTime;
  const ready = next && (!hasRealSongAudio(next) || !!getCachedSongAudio(next)?.complete);
  if (overlap && !missedOverlap && now >= at - .12) {
    // No hacer un traslape tardío si se perdió el punto de entrada.
    if (!ready || now >= at) missedOverlap = { next };
    else {
      clearTail();
      const dispose = detachMixForTail(at, end);
      selectSong(nextIndex);
      const outgoing = { dispose, timer: null };
      tail = outgoing;
      function finishTail() {
        if (tail !== outgoing) return;
        const remaining = end - state.ctx.currentTime;
        if (remaining > 0) outgoing.timer = setTimeout(finishTail, remaining * 1000);
        else clearTail();
      }
      finishTail();
      startNext(at);
      return true;
    }
  }
  if (next && ready && !missedOverlap && (mode === 'instant' || mode === 'overlap') &&
      !overlap && now >= end - .12 && now < end) {
    clearTail();
    const dispose = detachMixForTail(end, end);
    selectSong(nextIndex);
    const outgoing = { dispose, timer: null };
    tail = outgoing;
    outgoing.timer = setTimeout(() => {
      if (tail === outgoing) clearTail();
    }, Math.max(0, end - state.ctx.currentTime) * 1000 + 20);
    startNext(end);
    return true;
  }
  if (now < end) return false;
  const waitForPlay = missedOverlap || !ready || mode === 'stop';
  if (!next) stopAll();
  else {
    selectSong(nextIndex);
    if (!waitForPlay) startNext();
    else if (!ready) say('CARGANDO SIGUIENTE CANCIÓN — PULSA PLAY CUANDO ESTÉ LISTA');
  }
  return true;
}

function startNext(at = null) {
  const revision = playbackRevision;
  state.isStartingPlay = true;
  play({ at, fromBeginning: true, allowLateStart: true }).catch(error => {
    if (revision !== playbackRevision) return;
    hardStop();
    updateTransport();
    say('NO SE PUDO INICIAR LA SIGUIENTE CANCIÓN');
    console.warn('Error de transición', error);
  }).finally(() => {
    if (revision === playbackRevision) state.isStartingPlay = false;
  });
}

export function setMasterLevel(db) {
  state.STEMS.master.gain = dbToGain(db);
  applyMix();
  syncChannels();
}

export function getQueuedSection() {
  return queuedSection?.song === state.SONG ? queuedSection : null;
}

export function queueSection(index) {
  const section = state.SONG?.sections?.[index];
  const target = Number(section?.bar) * 16;
  if (!Number.isFinite(target)) return;
  if (!state.isPlaying) {
    jumpTo(target);
    return;
  }
  if (queuedSection?.scheduled) return;
  clearTail();
  missedOverlap = null;
  if (queuedSection?.index === index) {
    queuedSection = null;
    return;
  }
  const position = Math.max(0, getBeat16());
  const active = getCurrentSectionInfo(position).sec;
  const end = Math.min(Number(state.SONG.total16ths) || 128, (Number(active?.bar) + Number(active?.len)) * 16);
  if (!Number.isFinite(end) || end <= position) return;
  queuedSection = { song: state.SONG, index, target, end, scheduled: false };
}


export function getCurrentSectionInfo(curPos16) {
  if (!state.SONG) return { sec: { name: 'VACÍO', bar: 0, len: 4 }, idx: -1, curBar: 0 };
  const tot16 = state.SONG.total16ths || 128;
  curPos16 = ((curPos16 % tot16) + tot16) % tot16;
  const curBar = Math.floor(curPos16 / 16);
  let idx = 0;
  const secs = state.SONG.sections || [];
  if (secs.length === 0) return { sec: null, idx: -1, curBar };
  for (let i = 0; i < secs.length; i++) {
    const s = secs[i];
    if (curBar >= Number(s.bar) && curBar < Number(s.bar) + Number(s.len)) {
      idx = i;
      break;
    }
  }
  return { sec: secs[idx] || secs[0], idx, curBar };
}



export function schedule() {
  if (advanceAtSongEnd()) return;
  const queued = getQueuedSection();
  if (queued && !queued.scheduled) {
    const at = state.anchor.time + (queued.end - state.anchor.t16) * state.stepSec();
    if (at <= state.ctx.currentTime + .12) {
      const boundary = Math.max(at, state.ctx.currentTime + .01);
      queued.scheduled = true;
      outgoingAnchor = state.anchor;
      state.anchor = { t16: queued.target, time: boundary };
      state.current16th = queued.target;
      state.next16thTime = boundary;
      state.isSectionLooping = false;
      state.loopSectionIdx = -1;
      if (Object.keys(state.REAL_STEM_BUFFERS).length) {
        playRealStems(queued.target * state.stepSec(), 0, boundary, true)
          .catch(() => say('NO SE PUDO CAMBIAR DE SECCIÓN'));
      }
    }
  }
  while (state.next16thTime < state.ctx.currentTime + .12) {
    if (state.isSectionLooping && state.current16th >= 0 && !state.SONG.backendStems) {
      const tot16 = state.SONG.total16ths || 128;
      const curPos16 = ((state.current16th % tot16) + tot16) % tot16;
      let curSec = null;
      if (state.SONG.sections && state.loopSectionIdx >= 0 && state.loopSectionIdx < state.SONG.sections.length) {
        curSec = state.SONG.sections[state.loopSectionIdx];
      } else if (state.SONG.sections) {
        for (const s of state.SONG.sections) {
          if (curPos16 >= s.bar * 16 && curPos16 < (s.bar + s.len) * 16) {
            curSec = s;
            break;
          }
        }
      }
      if (curSec) {
        const secStart16 = curSec.bar * 16;
        const secEnd16 = (curSec.bar + curSec.len) * 16;
        if (curPos16 >= secEnd16 - 1) {
          const beatOffset = state.current16th - curPos16;
          state.current16th = beatOffset + secStart16;
          state.anchor.t16 = state.current16th;
          state.anchor.time = state.next16thTime;
        }
      }
    }

    if (state.next16thTime >= state.ctx.currentTime) {
      scheduleStep(state.current16th, state.next16thTime);
    }
    state.current16th++;
    state.next16thTime += state.stepSec();
  }
}



export function getBeat16() {
  if (!state.isPlaying) return state.pausedBeat * 4;
  const processingDelay = state.transposeSemitones !== 0 ? state.REAL_STRETCH_LATENCY : 0;
  const time = state.ctx.currentTime - processingDelay;
  if (outgoingAnchor && time >= state.anchor.time) {
    outgoingAnchor = null;
    queuedSection = null;
  }
  const anchor = outgoingAnchor || state.anchor;
  return anchor.t16 + (time - anchor.time) / state.stepSec();
}


export async function togglePlay() {
  if (state.audioLoading || state.isStartingPlay) {
    if (state.audioLoading) say("ESPERE, CARGANDO AUDIO...");
    return;
  }
  if (state.isPlaying) {
    pause();
  } else {
    state.isStartingPlay = true;
    try {
      await play();
    } catch (error) {
      console.error('No se pudo iniciar la reproducción:', error);
      stopRealStems();
      state.isPlaying = false;
      updateTransport();
      const transposeFailed = state.transposeSemitones !== 0;
      if (transposeFailed) {
        state.transposeTargetKey = null;
        state.transposeSemitones = 0;
        if (state.SONG) state.SONG.transposeKey = null;
        setTransposeCompensationDelay(0);
        syncModernUI(typeof state.current16th === 'number' ? state.current16th : 0);
      }
      say(transposeFailed
        ? 'TRANSPOSITOR NO DISPONIBLE; SE RESTABLECIÓ EL TONO ORIGINAL'
        : 'NO SE PUDO INICIAR EL AUDIO');
    } finally {
      state.isStartingPlay = false;
    }
  }
}



export async function play({ at = null, fromBeginning = false, allowLateStart = false } = {}) {
  if (!state.SONG) {
    say("EL SETLIST ESTÁ VACÍO. SUBE TUS STEMS PRIMERO.");
    return;
  }
  const mySong = state.SONG; // capturamos la cancion original para evitar doble reproduccion
  const revision = playbackRevision;
  await initAudio();
  if (state.ctx.state === 'suspended') {
    try {
      await state.ctx.resume();
    } catch (err) {
      say('PULSA PLAY PARA ACTIVAR EL AUDIO');
      return;
    }
  }
  if (state.kill) {
    const now = state.ctx.currentTime;
    state.kill.gain.cancelScheduledValues(now); state.kill.gain.setValueAtTime(1, now);
  }
  
  let start = fromBeginning ? 0 :
    state.pausedBeat > 0 ? Math.round(state.pausedBeat * 4) : (state.countOn ? -16 : 0);
  const usesRealStems = !!(state.SONG.backendStems || state.SONG.downloadUrl || state.SONG.folderId);
  let delaySeconds = 0;
  let startSeconds = 0;
  if (usesRealStems) {
    if (Object.keys(state.REAL_STEM_BUFFERS).length === 0) await loadRealStems(state.SONG);
    if (start < 0) delaySeconds = Math.abs(start) * state.stepSec();
    else startSeconds = start * state.stepSec();
    if (state.SONG !== mySong || revision !== playbackRevision || !Object.keys(state.REAL_STEM_BUFFERS).length) return;
    if (state.transposeSemitones !== 0) await ensureRealStretchRoutes();
  }

  if (state.SONG !== mySong || revision !== playbackRevision) return;
  if (allowLateStart && at !== null && at <= state.ctx.currentTime) at = state.ctx.currentTime + .01;
  if (at !== null && at <= state.ctx.currentTime) throw new Error('El inicio sincronizado llegó tarde.');
  const transportStartTime = at ?? state.ctx.currentTime + 0.1;
  state.anchor = { t16: start, time: transportStartTime }; state.current16th = start; state.next16thTime = state.anchor.time;
  if (usesRealStems) {
    await playRealStems(startSeconds, delaySeconds, transportStartTime + delaySeconds, false,
      () => revision === playbackRevision && state.SONG === mySong);
  }
  
  if (state.SONG !== mySong || revision !== playbackRevision) return;
  state.timer = setInterval(schedule, 25); schedule();
  state.isPlaying = true; state.started = true; updateTransport();
  preloadedNext = state.SONGS_DATA[state.currentSongIdx + 1];
  preloadSongAudio(preloadedNext);
  const info = getCurrentSectionInfo(state.current16th);
  say('EN DIRECTO — ' + (info.sec ? info.sec.name : 'LIBRE'));
}



export function hardStop() {
  playbackRevision++;
  state.isStartingPlay = false;
  missedOverlap = null;
  preloadedNext = null;
  clearTail();
  queuedSection = outgoingAnchor = null;
  const now = state.ctx ? state.ctx.currentTime : 0;
  if (state.timer) { clearInterval(state.timer); state.timer = null; }
  if (state.kill && state.ctx) {
    state.kill.gain.cancelScheduledValues(now);
    state.kill.gain.setValueAtTime(1, now);
    state.kill.gain.linearRampToValueAtTime(.0001, now + .07);
  }
  
  stopRealStems();
  
  state.activeNodes.forEach(n => { try { n.stop(now + .08); } catch (_) {} }); state.activeNodes.clear();
  if (state.delayFB && state.ctx) state.delayFB.gain.setTargetAtTime(.0001, now, .05);
  state.isPlaying = false;
}



export function pause() {
  const b = getBeat16() / 4;
  state.pausedBeat = Math.max(0, b);
  hardStop(); updateTransport(); say('PAUSA — POSICIÓN GUARDADA');
}



export function stopAll() {
  state.pausedBeat = 0; state.current16th = 0; hardStop(); updateTransport(); say('STOP — COMPÁS 1');
  drawHeroWaveform();
  document.querySelectorAll('.b-flash-dot').forEach(d => d.classList.remove('on'));
}



export function jumpTo(b16) {
  if (!Number.isFinite(b16) || !state.SONG) return;
  queuedSection = outgoingAnchor = null;
  clearTail();
  missedOverlap = null;
  const tot16 = state.SONG && state.SONG.total16ths ? state.SONG.total16ths : 128;
  b16 = ((b16 % tot16) + tot16) % tot16;
  const info = getCurrentSectionInfo(b16);
  if (!state.ctx || !state.isPlaying) {
    state.pausedBeat = b16 / 4;
    state.current16th = b16;
    say('POSICIÓN → COMPÁS ' + (Math.floor(b16 / 16) + 1));
    return;
  }
  const now = state.ctx.currentTime;
  state.kill.gain.cancelScheduledValues(now);
  state.kill.gain.setValueAtTime(1, now);
  state.kill.gain.linearRampToValueAtTime(.0001, now + .02);
  state.kill.gain.setValueAtTime(1, now + .1);
  const restartStems = Object.keys(state.REAL_STEM_BUFFERS).length > 0;
  if (restartStems) stopRealStems();
  state.activeNodes.forEach(n => { try { n.stop(now + .03); } catch (_) {} }); state.activeNodes.clear();
  state.anchor = { t16: b16, time: now + .06 }; state.current16th = b16; state.next16thTime = state.anchor.time;
  if (restartStems) playRealStems(b16 * state.stepSec(), 0, state.anchor.time).catch(() => say('NO SE PUDIERON REINICIAR LOS STEMS'));
  say(info.sec?.name || 'CAMBIO DE POSICIÓN');
}



export function setBpm(v, silent) {
  state.bpm = state.clamp(Math.round(v * 10) / 10, 60, 180);
  const disp = state.$('#bpmDisp');
  if (disp) disp.textContent = state.bpm.toFixed(1);
  if (state.isPlaying && state.ctx) {
    const b = Math.round(getBeat16()), now = state.ctx.currentTime;
    state.anchor = { t16: b, time: now + .03 }; state.current16th = b; state.next16thTime = state.anchor.time;
  }
  if (!silent) say('TEMPO ' + state.bpm.toFixed(1) + ' BPM');
}


/* ---------- Mezclador de Audio ---------- */

export function applyMix() {
  if (!state.ctx) return;
  const anySolo = state.stemKeys.some(s => state.STEMS[s] && state.STEMS[s].solo);
  const now = state.ctx.currentTime;
  for (const s of state.stemKeys) {
    const st = state.STEMS[s];
    if (!st) continue;
    ensureStemAudioNode(s);
    let g = st.muted ? 0 : st.gain;
    if (!isMixerPriorityCue(s) && s !== 'talkback' && anySolo && !st.solo) g = 0;
    if (st.faderNode) st.faderNode.gain.setTargetAtTime(g, now, .015);
  }
  if (state.masterG) state.masterG.gain.setTargetAtTime(state.STEMS.master.muted ? 0 : state.STEMS.master.gain, now, .015);
}



export function syncChannels() {
  const mixerEl = state.$('#mixer');
  if (mixerEl) {
    state.stemKeys.concat('master').forEach(s => {
      const st = state.STEMS[s];
      if (!st) return;
      const f = mixerEl.querySelector(`.fader[data-stem="${s}"]`);
      if (f) { f.style.setProperty('--v', gainToPosition(st.gain)); f.setAttribute('aria-valuenow', gainToDb(st.gain).toFixed(1)); f.setAttribute('aria-valuetext', state.fmtDb(st.gain)); }
      const db = mixerEl.querySelector(`.ch-db[data-stem="${s}"]`); if (db) db.textContent = state.fmtDb(st.gain);
      const bm = mixerEl.querySelector(`.chbtn.bm[data-stem="${s}"]`); if (bm) bm.classList.toggle('on', st.muted);
      const bs = mixerEl.querySelector(`.chbtn.bs[data-stem="${s}"]`); if (bs) bs.classList.toggle('on', st.solo);
    });
  }

  // Sincronizar Fader Master y controles en la Vista Show
  const smFader = document.getElementById('stageMasterFader');
  const smTrack = document.getElementById('stageMasterTrack');
  if (smFader) {
    smFader.style.setProperty('--v', gainToPosition(state.STEMS.master.gain));
    smFader.setAttribute('aria-valuemin', -60); smFader.setAttribute('aria-valuemax', 10); smFader.setAttribute('aria-valuenow', gainToDb(state.STEMS.master.gain).toFixed(1));
  }
  if (smTrack) {
    smTrack.style.setProperty('--v', gainToPosition(state.STEMS.master.gain));
    smTrack.setAttribute('aria-valuemin', -60); smTrack.setAttribute('aria-valuemax', 10); smTrack.setAttribute('aria-valuenow', gainToDb(state.STEMS.master.gain).toFixed(1));
  }
  const smDb = document.getElementById('stageMasterDbText');
  if (smDb) smDb.textContent = state.fmtDb(state.STEMS.master.gain);
  const smMute = document.getElementById('stageMasterMuteBtn');
  if (smMute) smMute.classList.toggle('on', state.STEMS.master.muted);
  const smStatus = document.getElementById('stageMasterStatus');
  if (smStatus) {
    smStatus.textContent = state.STEMS.master.muted ? 'SILENCIADO' : 'ACTIVO';
    smStatus.classList.toggle('muted', state.STEMS.master.muted);
  }
  const moSlider = document.getElementById('moMasterSlider');
  if (moSlider && state.STEMS.master) {
    moSlider.value = gainToDb(state.STEMS.master.gain);
    const moDb = document.getElementById('moMasterDb');
    if (moDb) moDb.innerText = state.fmtDb(state.STEMS.master.gain);
  }
}

export function initializeTransport() {
  const slider = document.getElementById('moMasterSlider');
  slider?.addEventListener('input', () => setMasterLevel(Number(slider.value)));


state.isSectionLooping = false;

state.loopSectionIdx = -1;

state.selectedSectionIdx = -1;


/* ---------- Transporte Principal ---------- */
state.isStartingPlay = false;
}

