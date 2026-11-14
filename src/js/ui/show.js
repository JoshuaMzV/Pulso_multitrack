import { state } from '../state/store.js';
import { getBeat16, getCurrentSectionInfo, getQueuedSection, queueSection } from '../audio/transport.js';
import { drawAllMeters, drawStageStereoMeter } from './meters.js';
import { getSongRootKey, formatMusicalKey } from '../audio/pads.js';
import { getShortSectionCode } from './controls.js';


export function say(msg) {
  const line = state.$('#statusLine');
  if (line) line.textContent = msg;
  state.statusMode = 'msg';
  clearTimeout(state.statusTimer);
  state.statusTimer = setTimeout(() => state.statusMode = 'auto', 2400);
}


export function statusAuto() {
  const el = state.$('#statusLine');
  if (!el) return;
  if (!state.isPlaying) {
    el.textContent = state.started ? 'PAUSA — POSICIÓN COMPÁS ' + (Math.floor(state.pausedBeat / 4) + 1) : 'STANDBY — CLICK ACTIVO · PULSA PLAY O [ESPACIO]';
    return;
  }
  const b = getBeat16() / 4;
  const info = getCurrentSectionInfo(getBeat16());
  el.textContent = b < 0 ? 'CUENTA DE ENTRADA · ' + state.curCount : 'EN DIRECTO — ' + info.sec.name;
}


/* ==========================================================================
   WAVEFORM AUDACITY SUPERIOR (RECTÁNGULO ESCENARIO)
   ========================================================================== */

export function getWaveformPeak(songId, ratio) {
  const n1 = Math.abs(Math.sin(ratio * 345.67) * 43758.5453 % 1);
  const n2 = Math.abs(Math.cos(ratio * 123.89) * 21415.9265 % 1);
  const micro = 0.68 + 0.32 * n1;

  if (songId === 0) {
    let env = 0.20;
    if (ratio < 0.14) env = 0.18 + ratio * 1.2;
    else if (ratio < 0.35) env = 0.38 + Math.sin(ratio * 22) * 0.14;
    else if (ratio < 0.55) env = 0.78 + Math.sin(ratio * 28) * 0.18;
    else if (ratio < 0.68) env = 0.44 + Math.sin(ratio * 16) * 0.12;
    else if (ratio < 0.88) env = 0.90 + Math.sin(ratio * 32) * 0.14;
    else env = Math.max(0.12, 0.50 - (ratio - 0.88) * 3.2);
    return Math.min(1.0, Math.max(0.10, env * micro + n2 * 0.12));
  } else {
    let env = 0.45;
    if (ratio < 0.15) env = 0.62 + Math.sin(ratio * 28) * 0.16;
    else if (ratio < 0.40) env = 0.52 + Math.sin(ratio * 20) * 0.14;
    else if (ratio < 0.65) env = 0.86 + Math.sin(ratio * 30) * 0.14;
    else if (ratio < 0.85) env = 0.94 + Math.sin(ratio * 36) * 0.10;
    else env = Math.max(0.12, 0.52 - (ratio - 0.85) * 2.8);
    return Math.min(1.0, Math.max(0.12, env * micro + n2 * 0.15));
  }
}



export function drawHeroWaveform() {
  if (!state.SONG) return;
  const canvas = document.getElementById('heroWaveformCanvas');
  if (!canvas) return;
  const rect = canvas.getBoundingClientRect();
  const w = rect.width, h = rect.height;
  if (w === 0 || h === 0) return;

  const dpr = window.devicePixelRatio || 1;
  const targetW = Math.floor(w * dpr), targetH = Math.floor(h * dpr);
  if (canvas.width !== targetW || canvas.height !== targetH) {
    canvas.width = targetW; canvas.height = targetH;
  }

  const ctx2 = canvas.getContext('2d');
  ctx2.save();
  ctx2.scale(dpr, dpr);
  ctx2.clearRect(0, 0, w, h);

  const tot16 = state.SONG.total16ths || 128;
  const b16 = getBeat16();
  const progressRatio = ((b16 % tot16) + tot16) % tot16 / tot16;
  const barW = 2.0, gap = 1.4, pitch = barW + gap;
  const numBars = Math.floor(w / pitch);
  const now = Date.now();

  for (let i = 0; i < numBars; i++) {
    const x = i * pitch;
    const barRatio = (i + 0.5) / numBars;
    let peak = getWaveformPeak(state.currentSongIdx, barRatio);

    if (state.isPlaying && Math.abs(barRatio - progressRatio) < 0.05) {
      const flutter = Math.sin(now / 60 + i * 1.5) * 0.12;
      peak = Math.min(1.0, Math.max(0.10, peak + flutter));
    }

    const maxH = h - 2.5;
    const barH = Math.max(1.8, peak * maxH);
    const y = h - barH;
    const isPlayed = barRatio <= progressRatio;
    const isPlayhead = Math.abs(barRatio - progressRatio) < (pitch / w);

    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    if (isPlayhead) ctx2.fillStyle = isLight ? '#0E0C0A' : '#ffffff';
    else if (isPlayed) ctx2.fillStyle = isLight ? '#4B6227' : '#E9A23B';
    else ctx2.fillStyle = isLight ? 'rgba(14, 12, 10, 0.72)' : 'rgba(255, 255, 255, 0.22)';

    ctx2.beginPath();
    if (ctx2.roundRect) ctx2.roundRect(x, y, barW, barH, [1, 1, 0, 0]);
    else ctx2.rect(x, y, barW, barH);
    ctx2.fill();
  }
  ctx2.restore();
}


/* ==========================================================================
   BUCLE PRINCIPAL DE ANIMACIÓN Y SINCRONIZACIÓN
   ========================================================================== */

export function frame() {
  requestAnimationFrame(frame);
  const b16 = getBeat16(), b = b16 / 4;
  const counting = state.isPlaying && b < 0;
  const db = counting ? 0 : Math.max(0, b);

  const playhead = state.$('#playhead');
  const tot16 = state.SONG && state.SONG.total16ths ? state.SONG.total16ths : 128;
  if (playhead) playhead.style.left = Math.max(0, b16 / tot16 * 100) + '%';

  // 2. Reloj de la Consola
  const barDisp = state.$('#barDisp');
  const timeDisp = state.$('#timeDisp');
  if (counting) {
    state.curCount = Math.max(1, Math.ceil(-b));
    if (barDisp) barDisp.textContent = 'CUENTA · ' + state.curCount;
  } else {
    if (barDisp) barDisp.textContent = 'COMPÁS ' + (Math.floor(db / 4) + 1) + '.' + (Math.floor(db) % 4 + 1);
    if (timeDisp) timeDisp.textContent = state.fmtTime(db * 60 / state.bpm);
  }

  // 3. Puntos de Beat en la Consola
  const bi = counting ? Math.floor(b + 4) % 4 : Math.floor(db) % 4;
  document.querySelectorAll('.beat-dot').forEach((d, i) => d.classList.toggle('on', i === bi));

  // 4. Resaltado de Sección Activa (Timeline y Pads de Edición)
  const info = getCurrentSectionInfo(b16);
  const si = info.idx;
  if (si !== state.curSecIdx || counting) {
    state.curSecIdx = si;
    document.querySelectorAll('.tl-sec').forEach((s, i) => s.classList.toggle('active', i === si && !counting));
    document.querySelectorAll('#editionSecPads .pad').forEach((p, i) => p.classList.toggle('active', i === si && !counting));
  }

  // 5. Medidores LED y Estado
  if (state.ctx) drawAllMeters();
  if (state.statusMode === 'auto') statusAuto();

  // 6. Sincronización con la Vista de Escenario (Show View)
  updateShowView(b16, db);
}



// ================= MODERN UI SYNC =================

export function syncModernUI(b16) {
  if (!state.SONG) return;
  const sl = state.ALL_SETLISTS[state.currentSetlistIdx];
  if (sl) {
    const elSlName = document.getElementById('moSetlistName');
    if (elSlName) elSlName.innerText = sl.name.toUpperCase();
    const elSlCount = document.getElementById('moSetlistCount');
    if (elSlCount) elSlCount.innerText = `${state.currentSongIdx + 1}/${sl.songs.length}`;
  }

  // Hero Card
  const elTitle = document.getElementById('moHeroTitle');
  if (elTitle) elTitle.innerText = state.SONG.title || 'SIN TITULO';
  const elArtist = document.getElementById('moHeroArtist');
  if (elArtist) elArtist.innerText = state.SONG.artist || 'ARTISTA';
  
  const hKey = document.getElementById('moHeroKey');
  if (hKey) {
    const originalKey = getSongRootKey(state.SONG.key || 'C');
    const currentKey = state.transposeTargetKey || originalKey;
    hKey.innerText = currentKey;
    hKey.classList.toggle('transposed', state.transposeSemitones !== 0);
    hKey.title = state.transposeSemitones === 0
      ? `Tonalidad original: ${formatMusicalKey(state.SONG.key || 'C')}. Pulsa para transponer.`
      : `Original: ${formatMusicalKey(state.SONG.key || 'C')} · Transpuesta: ${currentKey}. Pulsa para cambiar.`;
    hKey.setAttribute('aria-label', `Tonalidad ${currentKey}. Cambiar transposición`);
  }
  const hTempo = document.getElementById('moHeroTempo');
  if (hTempo) hTempo.innerText = `${state.SONG.bpm || 120} BPM - ${state.SONG.signature || '4/4'}`;

  // Fondo Hero
  const hCard = document.getElementById('moHeroCard');
  if (hCard) {
    if (state.SONG.cover) hCard.style.backgroundImage = `url(${state.SONG.cover})`;
    else hCard.style.backgroundImage = 'none';
  }

  // Next Song Card
  const nextCard = document.getElementById('moNextCard');
  if (nextCard && sl && state.currentSongIdx < sl.songs.length - 1) {
    nextCard.style.display = 'flex';
    const nSong = sl.songs[state.currentSongIdx + 1];
    document.getElementById('moNextTitle').innerText = nSong.title || 'Siguiente';
    document.getElementById('moNextArtist').innerText = nSong.artist || '';
    document.getElementById('moNextKey').innerText = formatMusicalKey(nSong.key || '-');
    const nThumb = document.getElementById('moNextThumb');
    if (nSong.cover) nThumb.style.backgroundImage = `url(${nSong.cover})`;
    else nThumb.style.backgroundImage = 'none';
  } else if (nextCard) {
    nextCard.style.display = 'none';
  }

  // Secciones y progreso (si b16 es enviado)
  if (Number.isFinite(b16)) {
    const sec = getCurrentSectionInfo ? getCurrentSectionInfo(b16) : null;
    const sName = document.getElementById('moHeroSec');
    const sNext = document.getElementById('moHeroNextSec');
    const sTime = document.getElementById('moHeroTime');
    const sLoop = document.getElementById('moHeroLoopBtn');
    
    if (sec && sec.sec) {
      const active = sec.sec;
      const nextSec = (state.SONG.sections && sec.idx + 1 < state.SONG.sections.length) ? state.SONG.sections[sec.idx + 1] : null;
      sName.innerText = active.name || '';
      const queued = getQueuedSection();
      const target = queued && state.SONG.sections[queued.index];
      sNext.innerText = target ? `→ EN COLA: ${target.name}` : nextSec ? `→ SIGUE ${nextSec.name}` : '→ FIN';
      const end16 = queued?.end ?? (Number(active.bar) + Number(active.len)) * 16;
      const remaining = (end16 - b16) * state.stepSec();
      const remSecs = Number.isFinite(remaining) ? Math.max(0, Math.ceil(remaining)) : 0;
      let m = Math.floor(remSecs / 60);
      let s = Math.floor(remSecs % 60);
      sTime.innerText = `${m}:${s < 10 ? '0' : ''}${s}`;
      
      if (sLoop) {
        const looping = state.isSectionLooping && state.loopSectionIdx === sec.idx;
        sLoop.setAttribute('aria-pressed', String(looping));
        sLoop.disabled = false;
      }
    } else if (sLoop) {
      sLoop.setAttribute('aria-pressed', 'false');
      sLoop.disabled = true;
    }

    // Progreso Total
    const progBar = document.getElementById('moHeroProgress');
    if (progBar && state.SONG.total16ths) {
      let pct = (b16 / state.SONG.total16ths) * 100;
      progBar.style.width = Math.min(100, Math.max(0, pct)) + '%';
    }
    
    // Sincronizar timeline carrusel
    syncModernArranger(b16);
  }
}



export function syncModernArranger(b16) {
  const container = document.getElementById('moArrangerCarousel');
  if (!container || !state.SONG.sections) return;
  const sections = state.SONG.sections;
  const labels = JSON.stringify(sections.map(section => section.name));
  if (container.dataset.labels !== labels) {
    container.dataset.labels = labels;
    container.replaceChildren(...sections.map((section, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'mo-arr-block';
      button.id = `moArrBlock_${index}`;
      button.innerHTML = '<span class="mo-arr-top"><span></span><span class="mo-arr-chk" aria-hidden="true">✓</span></span><span class="mo-arr-wave"></span>';
      button.querySelector('.mo-arr-top span').textContent = getShortSectionCode(section.name);
      button.setAttribute('aria-label', section.name);
      button.addEventListener('click', () => {
        queueSection(index);
        syncModernUI(getBeat16());
      });
      return button;
    }));
  }
  const queued = getQueuedSection();
  state.SONG.sections.forEach((sec, i) => {
    const el = container.children[i];
    const start16 = sec.bar * 16;
    const end16 = (Number(sec.bar) + Number(sec.len)) * 16;
    const active = b16 >= start16 && b16 < end16;
    const wasActive = el.classList.contains('active');
    el.classList.toggle('active', active);
    el.classList.toggle('passed', b16 >= end16);
    el.classList.toggle('queued', queued?.index === i);
    el.setAttribute('aria-pressed', String(queued?.index === i));
    if (active && !wasActive) {
      el.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    }
  });
}

// ===================================================


export function updateShowView(b16, db) {
  syncModernUI(b16);

  const tot16 = state.SONG && state.SONG.total16ths ? state.SONG.total16ths : 128;
  const progressRatio = ((b16 % tot16) + tot16) % tot16 / tot16;
  const progressPercent = (progressRatio * 100).toFixed(2);
  const stencilEl = document.getElementById('heroBlackStencil');
  const laserEl = document.getElementById('heroLaserWipe');
  if (stencilEl && laserEl) {
    stencilEl.style.clipPath = `polygon(${progressPercent}% 0%, 100% 0%, 100% 100%, ${progressPercent}% 100%)`;
    laserEl.style.left = `${progressPercent}%`;
  }

  // Tiempos formateados para la barra superior
  const sSec = 60 / state.bpm / 4;
  const elapsed = (((b16 % tot16) + tot16) % tot16) * sSec;
  const total = tot16 * sSec;
  const mE = Math.floor(elapsed / 60), sE = Math.floor(elapsed % 60);
  const mT = Math.floor(total / 60), sT = Math.round(total % 60);
  const hdrTimeMain = document.getElementById('headerTimeMain');
  const hdrTimeDur = document.getElementById('headerTimeDur');
  if (hdrTimeMain) hdrTimeMain.textContent = `${String(mE).padStart(2, '0')}:${String(sE).padStart(2, '0')}`;
  if (hdrTimeDur) hdrTimeDur.textContent = `0:00 / ${mT}:${String(sT).padStart(2, '0')}`;

  // Actualizar Nombre de la Sección en el Cuadro Neón
  const info = getCurrentSectionInfo(b16);
  const activeSec = info.sec;

  const badgeEl = document.getElementById('stageCurrentSecBadge');
  if (badgeEl) badgeEl.textContent = activeSec.name;
  const tagEl = document.getElementById('stageCurrentSecTag');
  if (tagEl) tagEl.textContent = getShortSectionCode(activeSec.name);

  // Actualizar marcadores circulares con anillo giratorio en la carátula
  const markers = document.querySelectorAll('#heroSectionMarkers .hsm-marker');
  markers.forEach((m, i) => {
    m.classList.toggle('active', i === info.idx);
  });

  // Medidor Estéreo de Escenario en Línea Ultra Delgada (L / R)
  drawStageStereoMeter();

  // Forma de onda estilo Audacity de la carátula
  drawHeroWaveform();
}



export function updateTransport() {
  const consoleEl = state.$('#editionConsole');
  if (consoleEl) consoleEl.classList.toggle('playing', state.isPlaying);
  const playBtn = state.$('#playBtn');
  if (playBtn) playBtn.classList.toggle('playing', state.isPlaying);

  const smLed = document.getElementById('stageMasterLed');
  if (smLed) smLed.classList.toggle('playing', state.isPlaying);

  const hdrIcon = document.getElementById('headerPlayIcon');
  if (hdrIcon) hdrIcon.setAttribute('data-lucide', state.isPlaying ? 'pause' : 'play');
  if (window.lucide) lucide.createIcons();
}

export function initializeShow() {


/* ---------- Línea de Estado Terminal ---------- */
state.statusMode = 'auto';
state.statusTimer = null;
state.curSecIdx = 0;
state.curCount = 4;

requestAnimationFrame(frame);
}

