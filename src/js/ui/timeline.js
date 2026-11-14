import { readEq } from '../audio/eq.js';
import { state } from '../state/store.js';
import { getSetlistStorageKey, saveCurrentSetlist } from './setlists.js';
import { getAuthToken } from '../services/auth.js';
import { say, syncModernUI } from './show.js';
import { renderStageSections } from './controls.js';
import { jumpTo } from '../audio/transport.js';



export function waveAmp(stem, t16) {
  const bar = Math.floor(t16 / 16) % 8, step = Math.floor(t16) % 16, sec = bar >> 1, L = state.SEC_LEVEL[sec];
  const type = state.STEMS[stem]?.type || stem;

  if (type === 'drums') {
    const on = step % 4 === 0 ? .95 : step % 2 === 0 ? .5 : .22;
    const rnd = state.jr(Math.floor(t16) + (stem === 'perc' ? 44 : stem === 'loop_fx' ? 88 : 0));
    return .12 + on * L * .85 * (.75 + .5 * rnd);
  }
  if (type === 'bass') {
    let on;
    if (sec === 0) on = step < 7 || (step >= 8 && step < 15);
    else if (sec < 3) on = !(step >= 3 && step < 6) && !(step === 15);
    else on = bar === 6 ? step < 12 : true;
    return on ? (stem === 'sub_bass' ? .62 + L * .28 : .48 + L * .22) : .07;
  }
  if (type === 'keys' || type === 'pad') {
    const seed = stem === 'strings' ? 1.9 : stem === 'organ' ? 3.4 : stem === 'pad_amb' ? 5.1 : 2.7;
    return .22 + L * .18 + .08 * state.jr(Math.floor(t16 * seed));
  }
  if (type === 'guitar') {
    const str = step % 2 === 0 ? .7 : .35;
    return .15 + str * L * .45 + .05 * state.jr(Math.floor(t16 * 1.5));
  }
  if (type === 'lead') {
    if (t16 < 64 && stem !== 'guit_el1') return .04;
    let a = .06;
    for (const [st, f, len] of state.SONG.melody) {
      if (t16 >= st && t16 < st + len) {
        a = .65 - .4 * (t16 - st) / len;
        break;
      }
    }
    return a;
  }
  // click o talkback
  return step % 4 === 0 ? .38 : .02;
}



export function fitCv(cv) {
  const dpr = window.devicePixelRatio || 1;
  const w = Math.max(1, Math.round(cv.clientWidth * dpr)), h = Math.max(1, Math.round(cv.clientHeight * dpr));
  if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; }
}



const waveformPeaks = new WeakMap();

// Picos aproximados en una escala común, sin normalizar cada pista por separado.
function getBufferPeaks(buffer, columns, duration) {
  const cached = waveformPeaks.get(buffer);
  if (cached?.columns === columns && cached.duration === duration) return cached.peaks;
  const peaks = new Float32Array(columns);
  const channels = Array.from({ length: buffer.numberOfChannels }, (_, i) => buffer.getChannelData(i));
  for (let col = 0; col < columns; col++) {
    const start = Math.floor(col / columns * duration * buffer.sampleRate);
    const end = Math.min(buffer.length, Math.ceil((col + 1) / columns * duration * buffer.sampleRate));
    const stride = Math.max(1, Math.floor((end - start) / 128));
    for (const channel of channels) {
      for (let i = start; i < end; i += stride) peaks[col] = Math.max(peaks[col], Math.abs(channel[i]));
    }
  }
  waveformPeaks.set(buffer, { columns, duration, peaks });
  return peaks;
}

export function drawWave(stem) {
  if (!state.SONG) return;
  const cv = state.waveCv[stem]; if (!cv || !cv.clientWidth) return;
  fitCv(cv);
  const g = cv.getContext('2d'), W = cv.width, H = cv.height, dpr = window.devicePixelRatio || 1;
  g.clearRect(0, 0, W, H);
  g.fillStyle = stem === 'click' ? 'rgba(92, 98, 108, .5)' : 'rgba(96, 103, 114, .85)';
  const cy = H / 2, cols = Math.max(8, Math.floor(W / (2 * dpr)));
  const tot16 = state.SONG.total16ths || 128;
  const buffer = state.REAL_STEM_BUFFERS?.[stem];
  const realSong = state.SONG.backendStems || state.SONG.downloadUrl || state.SONG.folderId;
  const peaks = buffer ? getBufferPeaks(buffer, cols, tot16 * 60 / state.SONG.bpm / 4) : null;
  const gain = state.STEMS[stem]?.gain ?? 1;
  const waveColor = document.documentElement.getAttribute('data-theme') === 'light' ? '#4A5D52' : '#9C948A';
  // La línea central conserva la continuidad visual durante silencios y carga.
  g.fillStyle = waveColor;
  g.globalAlpha = 0.5;
  g.fillRect(0, Math.floor(cy), W, Math.max(1, dpr));
  g.globalAlpha = 1;
  for (let i = 0; i < cols; i++) {
    const t16 = (i / cols) * tot16;
    const a = (peaks ? peaks[i] : realSong ? 0 : waveAmp(stem, t16)) * gain;
    const hp = Math.min(1, a) * (H / 2 - 2 * dpr);
    g.fillStyle = a > 1 ? '#D33A3A' : waveColor;
    g.fillRect(i * 2 * dpr, cy - hp, dpr, hp * 2);
  }
  cv.setAttribute('aria-label', `Forma de onda ${state.STEMS[stem]?.label || stem}, ${state.fmtDb(gain)}${realSong && !buffer ? ', cargando audio' : ''}`);
}



export function drawWaveAll() {
  if (!state.SONG) return;
  state.stemKeys.forEach(drawWave);
}


export function toggleArranger() {
  const p = document.getElementById('arrangerPanel');
  if (p) {
    p.classList.toggle('active');
  }
}



export function renderTimeline() {
  if (!state.SONG) return;
  const tlBand = state.$('#tlBand');
  const tlRuler = state.$('#tlRuler');
  const tlTracks = state.$('#tlTracks');
  const tlZoomCont = state.$('#tlZoomContainer');
  if (!tlBand || !tlRuler || !tlTracks || !tlZoomCont) return;

  tlZoomCont.style.setProperty('--tl-zoom', `${state.tlZoom * 100}%`);

  const tot16 = state.SONG.total16ths || 128;
  const totBars = Math.ceil(tot16 / 16);
  const barPct = 100 / totBars;

  tlBand.innerHTML = (state.SONG.sections||[]).map((s, idx) => {
    const pLeft = (s.bar / totBars) * 100;
    const pWidth = (s.len / totBars) * 100;
    const isSel = parseInt(idx) === state.selectedSectionIdx;
    const name = s.name || '';
    const SHORT_NAMES = { PRECORO:'PC', INSTRUMENTAL:'INS', INTERLUDIO:'INT', INTRO:'I', VERSO:'V', CORO:'C', PUENTE:'P', FINAL:'F', OUTRO:'O' };
    const shortName = SHORT_NAMES[name.toUpperCase()] || name.split(' ').map(w => w.charAt(0).toUpperCase()).join('');
    return `<div class="tl-sec ${isSel ? 'selected' : ''}" data-idx="${idx}" style="left:${pLeft}%;width:${pWidth}%">
      <div class="sec-handle left" data-idx="${idx}" data-dir="left"></div>
      <span class="tl-sec-name-full">${name}</span>
      <span class="tl-sec-name-short">${shortName}</span>
      <div class="sec-handle right" data-idx="${idx}" data-dir="right"></div>
    </div>`;
  }).join('');

  tlRuler.style.display = 'grid';
  tlRuler.style.gridTemplateColumns = `repeat(${totBars}, 1fr)`;
  
  let ruleHtml = '';
  const skip = 4;
  for (let i = 0; i < totBars; i++) {
    ruleHtml += `<div class="tl-rb" style="border-left: 1px solid ${(i % skip === 0) ? 'rgba(240, 165, 66, 0.4)' : 'var(--line)'}; font-family: var(--mono); font-size: 11px; font-weight: 800; color: var(--amber); line-height: 24px; padding-left: 4px; overflow: visible; display: flex; align-items: center; z-index: 2;">${(i % skip === 0) ? i + 1 : ''}</div>`;
  }
  tlRuler.innerHTML = ruleHtml;

  tlTracks.style.backgroundImage = "none";

  tlTracks.innerHTML = state.stemKeys.map(s =>
    `<div class="tl-row"><span class="tl-name" title="${state.STEMS[s]?.label || s}">${state.STEMS[s]?.label || s}</span><canvas class="tl-wave" data-stem="${s}" role="img" aria-label="Forma de onda ${state.STEMS[s]?.label || s}"></canvas></div>`
  ).join('');

  state.waveCv = {};
  tlTracks.querySelectorAll('.tl-wave').forEach(c => state.waveCv[c.dataset.stem] = c);
  setTimeout(drawWaveAll, 40);
  
  setTimeout(() => { if (window.lucide) window.lucide.createIcons(); }, 10);
  


  // Setup de Resizing y Dragging
  setupSectionResize();
}



export async function saveSections() {
  if (!state.SONG) return;
  // Sincronizar en el objeto de la canción activa dentro de la setlist actual
  if (Array.isArray(state.SONGS_DATA) && state.SONGS_DATA[state.currentSongIdx]) {
    state.SONGS_DATA[state.currentSongIdx].sections = JSON.parse(JSON.stringify(state.SONG.sections || []));
  }
  // Guardar en almacenamiento de setlist del grupo
  const storageKey = getSetlistStorageKey();
  if (storageKey && Array.isArray(state.ALL_SETLISTS)) {
    try { localStorage.setItem(storageKey, JSON.stringify(state.ALL_SETLISTS)); } catch (_) {}
  }

  // Persistir en backend por ID/carpeta/título de la canción
  const songIdentifier = state.SONG.folderId || state.SONG.id || state.SONG.title;
  if (songIdentifier) {
    try {
      await fetch(`/api/songs/${encodeURIComponent(songIdentifier)}/sections`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${getAuthToken()}`
        },
        body: JSON.stringify(state.SONG.sections || [])
      });
    } catch (err) {
      console.warn("No se pudo guardar secciones en el backend:", err);
    }
  }
}



export async function saveSongArranger(e) {
  if (e) e.stopPropagation();
  if (!state.SONG) {
    say('SELECCIONA UNA CANCIÓN PRIMERO');
    return;
  }

  const song = state.SONG;
  const btn = document.getElementById('btnSaveArranger');
  if (btn.disabled) return;
  btn.disabled = true;
  btn.textContent = 'Guardando…';
  try {
    song.mix = Object.fromEntries([...state.stemKeys, 'master']
      .filter(id => state.STEMS[id])
      .map(id => [id, { gain: state.STEMS[id].gain, muted: state.STEMS[id].muted,
        solo: state.STEMS[id].solo, eq: readEq(id) }]));
    song.transposeKey = state.transposeTargetKey || null;
    song.sections = JSON.parse(JSON.stringify(song.sections || []));
    const saved = await saveCurrentSetlist();
    if (saved) btn.textContent = 'Guardado';
  } finally {
    setTimeout(() => {
      btn.textContent = 'Guardar';
      btn.disabled = false;
    }, 900);
  }

}



export function setupSectionResize() {
  const tlBand = state.$('#tlBand');
  tlBand.querySelectorAll('.tl-sec').forEach(b => {
    let pressTimer = null;
    b.addEventListener('pointerdown', (e) => {
      if (pressTimer) clearTimeout(pressTimer);
      
      const idx = parseInt(b.dataset.idx);
      if (state.selectedSectionIdx !== idx) {
        state.selectedSectionIdx = idx;
        tlBand.querySelectorAll('.tl-sec').forEach(el => el.classList.remove('selected'));
        b.classList.add('selected');
      }
      
      const handle = e.target.closest('.sec-handle');
      if (handle) {
        state.draggingSection = { idx, dir: handle.dataset.dir, startX: e.clientX, origBar: state.SONG.sections[idx].bar, hasMoved: false };
      } else {
        state.draggingSection = { idx, dir: 'move', startX: e.clientX, origBar: state.SONG.sections[idx].bar, hasMoved: false };
      }
      
      e.preventDefault();
      
      pressTimer = setTimeout(async () => {
        if (state.draggingSection && !state.draggingSection.hasMoved) {
          const ds = state.draggingSection; // save reference
          state.draggingSection = null; // prevent pointerup from jumping
          if (confirm(`¿Eliminar sección "${state.SONG.sections[idx].name}"?`)) {
            state.SONG.sections.splice(idx, 1);
            if (state.selectedSectionIdx === idx) state.selectedSectionIdx = -1;
            else if (state.selectedSectionIdx > idx) state.selectedSectionIdx--;
            renderTimeline(); syncModernUI(0);
            renderStageSections();
            await saveSections();
          }
        }
      }, 700);

      const cancelPress = () => {
        if (pressTimer) clearTimeout(pressTimer);
        document.removeEventListener('pointerup', cancelPress);
      };
      document.addEventListener('pointerup', cancelPress);

      document.addEventListener('pointermove', state.onDocPointerMove);
      document.addEventListener('pointerup', state.onDocPointerUp);
    });
  });
}

export function initializeTimeline() {



/* ---------- Timeline y Formas de Onda (Exacto al Screenshot) ---------- */
state.waveCv = {};

state.SEC_LEVEL = [.5, .8, 1, .6];


state.tlZoom = 1.0;

window.saveSongArranger = saveSongArranger;


state.draggingSection = null;


state.onDocPointerMove = (e) => {
  if (!state.draggingSection || !state.SONG) return;
  const tlBand = state.$('#tlBand');
  const rect = tlBand.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const pct = Math.max(0, Math.min(1, x / rect.width));
  const totBars = Math.ceil((state.SONG.total16ths || 128) / 16);
  const hoverBar = Math.round(pct * totBars);
  
  const s = state.SONG.sections[state.draggingSection.idx];
  if (!s) return;

  if (Math.abs(e.clientX - state.draggingSection.startX) > 4) {
    state.draggingSection.hasMoved = true;
  }

  if (state.draggingSection.dir === 'left') {
    const endBar = s.bar + s.len;
    if (hoverBar < endBar) {
      s.bar = hoverBar;
      s.len = endBar - hoverBar;
    }
  } else if (state.draggingSection.dir === 'right') {
    if (hoverBar > s.bar) {
      s.len = hoverBar - s.bar;
    }
  } else if (state.draggingSection.dir === 'move') {
    const deltaPct = (e.clientX - state.draggingSection.startX) / rect.width;
    const deltaBars = Math.round(deltaPct * totBars);
    s.bar = Math.max(0, state.draggingSection.origBar + deltaBars);
  }
  
  const secEl = tlBand.querySelector(`.tl-sec[data-idx="${state.draggingSection.idx}"]`);
  if (secEl) {
    const pLeft = (s.bar / totBars) * 100;
    const pWidth = (s.len / totBars) * 100;
    secEl.style.left = `${pLeft}%`;
    secEl.style.width = `${pWidth}%`;
  }
};


state.onDocPointerUp = async (e) => {
  if (state.draggingSection) {
    if (!state.draggingSection.hasMoved && state.SONG) {
       const s = state.SONG.sections[state.draggingSection.idx];
       if (s) jumpTo(s.bar * 16);
    }
    state.draggingSection = null;
    document.removeEventListener('pointermove', state.onDocPointerMove);
    document.removeEventListener('pointerup', state.onDocPointerUp);
    renderTimeline(); syncModernUI(0);
    renderStageSections();
    await saveSections();
  }
};
}

