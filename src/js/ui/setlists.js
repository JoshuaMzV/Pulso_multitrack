import { state } from '../state/store.js';
import { drawHeroWaveform, say, syncModernUI } from './show.js';
import { renderSectionMarkers, renderStageSections } from './controls.js';
import { startPad, stopPad, getSongRootKey, formatMusicalKey, getKeyNoteIndex, formatPadNote, updatePadRadioUI } from '../audio/pads.js';
import { play, stopAll, syncChannels, applyMix } from '../audio/transport.js';
import { resetTransposeForCurrentSong, openTransposePicker } from '../audio/transpose.js';
import { orderMixerStemKeys, ensureStemAudioNode } from '../audio/engine.js';
import { updateStemCountBadge, renderMixer } from './mixer.js';
import { renderTimeline, drawWaveAll, saveSections } from './timeline.js';
import { loadRealStems } from '../audio/stems.js';
import { openAuthModal, getAuthToken } from '../services/auth.js';
import { drawStageStereoMeter } from './meters.js';
import { openServerUploadWizard, openAddSongChoiceModal } from '../services/catalog.js';



export function renderStageSlider() {
  const track = document.getElementById('stageSliderTrack');
  const countEl = document.getElementById('stageSliderCount');
  const vp = document.getElementById('stageSliderViewport');
  if (!track) return;

  if (countEl) countEl.textContent = `${state.SONGS_DATA.length} CANCIONES`;

  if (state.SONGS_DATA.length === 0) {
    track.style.paddingLeft = '16px';
    track.style.paddingRight = '16px';
    track.innerHTML = `
      <div style="display:flex; flex-direction:column; align-items:center; justify-content:center; height:165px; width:calc(100vw - 32px); max-width:560px; flex-shrink:0; margin:0 auto; color:var(--mut); border: 2px dashed var(--line2); border-radius:14px; cursor:pointer; box-sizing:border-box;" onclick="openAddSongChoiceModal()">
        <i data-lucide="plus-circle" style="width:32px;height:32px;margin-bottom:10px;color:var(--amber);"></i>
        <h3 style="font-size:14px;font-weight:800;color:var(--ink2);">EL SETLIST ESTÁ VACÍO</h3>
        <p style="font-size:11px;font-family:var(--mono);margin-top:6px;">Haz clic para agregar canciones (desde Nube o Local)</p>
      </div>
    `;
    if (window.lucide) lucide.createIcons();
    return;
  }

  const isCompact = window.innerHeight < 550 || (window.innerWidth <= 960 && window.innerHeight < 650);
  const cardH = isCompact ? 140 : 165;
  let cardW = isCompact ? 445 : 560;
  
  if (vp) {
    const vpW = vp.clientWidth || window.innerWidth;
    const maxCardW = cardW;
    cardW = Math.min(maxCardW, vpW - 32); // Responsive width
    const pad = Math.max(16, Math.floor((vpW - cardW) / 2));
    track.style.paddingLeft = pad + 'px';
    track.style.paddingRight = pad + 'px';
  }

  const maxFontSize = isCompact ? 36 : 46;
  const padding = 40;

  let html = '';

  for (let i = 0; i < state.SONGS_DATA.length; i++) {
    const s = state.SONGS_DATA[i];
    let preset = {
      bg: s.cover ? `url('${s.cover}')` : 'linear-gradient(135deg, #221E19 0%, #110F0D 100%)',
      bgPos: 'center center',
      keyIndex: 0
    };
    if (!s.backendStems && state.SONG_HERO_PRESETS[i]) {
       preset.bg = state.SONG_HERO_PRESETS[i].bg;
       preset.bgPos = state.SONG_HERO_PRESETS[i].bgPos || preset.bgPos;
    }
    
    const textTitle = (s.title || 'UNKNOWN').toUpperCase();
    const textWidthEst = textTitle.length * (maxFontSize * 0.65);
    let dynFontSize = maxFontSize;
    if (textWidthEst > (cardW - padding)) {
      dynFontSize = Math.floor(maxFontSize * ((cardW - padding) / textWidthEst));
      if (dynFontSize < 18) dynFontSize = 18;
    }

    const isActive = (i === state.currentSongIdx);

    if (isActive) {
      // Tarjeta Widescreen Activa con Troquelado, Waveform y Marcadores (${cardW}px x ${cardH}px)
      html += `
        <div class="slider-song-unit active" data-song-idx="${i}" id="sliderActiveUnit" style="width: ${cardW}px;">
          <div class="slider-card-box hero-active-card" id="heroCard" style="background-image: ${preset.bg}; background-position: ${preset.bgPos}; width: ${cardW}px; height: ${cardH}px;">
            <!-- Capa 0: Carátula de fondo -->
            <div class="hero-art-full" id="heroArtFull" style="background-image: ${preset.bg}; background-position: ${preset.bgPos};"></div>
            
            <!-- Capa 1: Fondo negro troquelado / Stencil -->
            <div class="hero-black-stencil" id="heroBlackStencil">
              <svg class="stencil-svg" viewBox="0 0 ${cardW} ${cardH}" preserveAspectRatio="xMidYMid meet">
                <defs>
                  <mask id="cutoutMask">
                    <rect x="0" y="0" width="${cardW}" height="${cardH}" fill="white" />
                    <text x="50%" y="50%" text-anchor="middle" dominant-baseline="middle" font-family="'Inter', sans-serif" font-weight="900" font-size="${dynFontSize}" fill="black" letter-spacing="1">${textTitle}</text>
                  </mask>
                  <filter id="whiteShadedFilter" x="-20%" y="-20%" width="140%" height="140%">
                    <feDropShadow dx="0" dy="0.8" stdDeviation="1.0" flood-color="#000000" flood-opacity="0.80" />
                  </filter>
                </defs>
                <rect x="0" y="0" width="${cardW}" height="${cardH}" fill="#0E0C0A" fill-opacity="0.80" mask="url(#cutoutMask)" />
                <text x="50%" y="50%" text-anchor="middle" dominant-baseline="middle" font-family="'Inter', sans-serif" font-weight="900" font-size="${dynFontSize}" fill="none" stroke="rgba(255, 255, 255, 0.55)" stroke-width="0.8" letter-spacing="1" filter="url(#whiteShadedFilter)" pointer-events="none">${textTitle}</text>
              </svg>
            </div>

            <!-- Capa 2: Waveform Canvas -->
            <div class="hero-waveform-strip" id="heroWaveformStrip">
              <canvas id="heroWaveformCanvas" class="hero-wave-canvas" style="width:${cardW}px;"></canvas>
            </div>

            <!-- Capa 3: Línea Láser brillante -->
            <div class="hero-laser-wipe" id="heroLaserWipe"></div>

            <!-- Capa 4: Acorde central -->
            <div class="hero-tone-center">
              <button type="button" class="hero-tone-badge" id="heroKeyBadge" aria-label="Cambiar tonalidad de la canción" aria-haspopup="dialog" aria-expanded="false" onclick="openTransposePicker()">
                <span id="heroKeyCurrent">${s.key}</span>
              </button>
            </div>
          </div>

          <!-- Marcadores de secciones con loop y aro naranja giratorio -->
          <div class="hero-section-markers" id="heroSectionMarkers"></div>
        </div>
      `;
    } else {
      // Tarjeta Compacta Deslizante Inactiva (con Carátula y detalles)
      html += `
        <div class="slider-song-unit inactive" data-song-idx="${i}" title="Clic para pasar a: ${s.title}">
          <div class="slider-card-box inactive-card" style="background-image: ${preset.bg}; background-position: ${preset.bgPos};">
            <div class="sc-dark-overlay"></div>
            <div class="sc-content">
              <div class="sc-top-bar">
                <span class="sc-num-badge">TEMA #${i + 1}</span>
                <span class="sc-stems-tag">${s.stems?.length || 5} STEMS</span>
              </div>
              <div class="sc-center-info">
                <h4 class="sc-title">${s.title}</h4>
              </div>
              <div class="sc-bot-bar">
                <div class="sc-meta-left">
                  <span class="sc-key-badge">${s.key}</span>
                  <span class="sc-bpm-tag">${s.bpm} BPM</span>
                </div>
                <span class="sc-play-hint"><i data-lucide="play-circle"></i> REPRODUCIR</span>
              </div>
            </div>
          </div>
        </div>
      `;
    }

    // Conector de transición interactivo entre canciones
    if (i < state.SONGS_DATA.length - 1) {
      const currentMode = getSongTransition(state.SONGS_DATA[i]);
      const modeInfo = state.TRANSITION_MODES[currentMode] || state.TRANSITION_MODES.pad;

      html += `
        <div class="slider-trans-connector" data-tidx="${i}" title="Transición hacia ${state.SONGS_DATA[i + 1].title}: ${modeInfo.label} (${modeInfo.desc}) - Clic para alternar modo">
          <button type="button" class="slider-trans-btn ${modeInfo.class}" data-tidx="${i}">
            <div class="stb-circle">
              <i data-lucide="arrow-right"></i>
            </div>
            <span class="stb-label">${modeInfo.label}</span>
          </button>
        </div>
      `;
    }
  }

  track.innerHTML = html;

  // Listeners de clics en tarjetas inactivas para transición directa y centrado
  track.querySelectorAll('.slider-song-unit.inactive').forEach(unit => {
    unit.addEventListener('click', () => {
      const targetSongId = +unit.dataset.songIdx;
      const tIdx = targetSongId > 0 ? targetSongId - 1 : 0;
      const transMode = getSongTransition(state.SONGS_DATA[tIdx]);
      executeTransitionToSong(targetSongId, transMode);
    });
  });

  // Listeners de clics en botones de transición (flechas entre canciones)
  track.querySelectorAll('.slider-trans-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const tIdx = +btn.dataset.tidx;
      cycleTransitionMode(tIdx);
    });
  });

  if (window.lucide) lucide.createIcons();

  // Redibujar canvas, marcadores y autocentrar suavemente el tema activo
  setTimeout(() => {
    drawHeroWaveform();
    renderSectionMarkers();
    centerSliderOnActiveSong();
  }, 40);
}



export function centerSliderOnActiveSong() {
  const vp = document.getElementById('stageSliderViewport');
  const track = document.getElementById('stageSliderTrack');
  const activeUnit = document.getElementById('sliderActiveUnit');
  if (vp && track && activeUnit) {
    const vpW = vp.clientWidth;
    const activeW = activeUnit.offsetWidth || 560;
    const pad = Math.max(24, Math.floor((vpW - activeW) / 2));
    track.style.paddingLeft = pad + 'px';
    track.style.paddingRight = pad + 'px';

    const activeCenter = activeUnit.offsetLeft + (activeW / 2);
    const target = activeCenter - (vpW / 2);
    vp.scrollTo({ left: Math.max(0, target), behavior: 'smooth' });
  }
}



const transitionLabels = {
  stop: 'Con pausa',
  instant: 'Al terminar',
  overlap: 'Traslape con fundido'
};
const transitionIcons = { stop: '⤓', instant: '↴', overlap: '⇄' };

function transitionLabel(index, mode) {
  return `Transición de la canción ${index + 1} a la ${index + 2}: ${transitionLabels[mode]}`;
}

export function getSongTransition(song) {
  const mode = song?.transition;
  return mode === 'instant' || mode === 'overlap' ? mode : 'stop';
}

export function cycleTransitionMode(index) {
  const song = state.SONGS_DATA[index];
  if (!song || index >= state.SONGS_DATA.length - 1) return;
  const modes = Object.keys(transitionLabels);
  song.transition = modes[(modes.indexOf(getSongTransition(song)) + 1) % modes.length];
  renderEditionSongList();
  renderStageSlider();
}

export function executeTransitionToSong(songId, mode) {
  if (mode === 'pad') {
    selectSong(songId);
    startPad(state.currentPadKeyIndex, state.currentPadKeyName);
    say(`TRANSICIÓN: PAD CONTINUO EN ${state.currentPadKeyName} → ${state.SONG.title}`);
  } else if (mode === 'instant' || mode === 'overlap') {
    stopPad();
    selectSong(songId).then(() => {
      if (state.currentSongIdx === songId && !state.isPlaying && !state.isStartingPlay) {
        return play({ fromBeginning: true });
      }
    }).catch(() => say('NO SE PUDO INICIAR LA CANCIÓN'));
    say(`TRANSICIÓN DIRECTA: EN PLAY → ${state.SONG.title}`);
  } else {
    stopAll();
    stopPad();
    selectSong(songId);
    say(`TRANSICIÓN: EN PAUSA (LISTO) → ${state.SONG.title}`);
  }
}


/* ---------- Selección Unificada de Canción en Setlist ---------- */

export function selectSong(songId) {
  if (songId < 0 || songId >= state.SONGS_DATA.length) return Promise.resolve();
  stopAll();
  state.currentSongIdx = songId;
  state.SONG = state.SONGS_DATA[songId];
  resetTransposeForCurrentSong();
  state.bpm = state.SONG.bpm;
  state.loopSectionIdx = -1;
  state.isSectionLooping = false;
  state.selectedSectionIdx = -1;

  // Asegurar que cada canción tenga su propia lista de secciones independiente
  if (state.SONG) {
    if (!state.SONG.sections?.length) {
      const matchBack = (typeof state.LOCAL_BACKEND_SONGS !== 'undefined' ? state.LOCAL_BACKEND_SONGS : []).find(bs =>
        (bs.id && (bs.id === state.SONG.id || bs.id === state.SONG.folderId)) ||
        (bs.title && state.SONG.title && bs.title.toLowerCase() === state.SONG.title.toLowerCase())
      );
      if (matchBack && Array.isArray(matchBack.sections) && matchBack.sections.length > 0) {
        state.SONG.sections = JSON.parse(JSON.stringify(matchBack.sections));
      } else {
        state.SONG.sections = []; // Cada canción tiene sus propias secciones, no una plantilla fija
      }
    } else {
      state.SONG.sections = JSON.parse(JSON.stringify(state.SONG.sections));
    }
    state.SONGS_DATA[songId].sections = state.SONG.sections;
  }

  // Actualizar selección activa en el Sidebar de Edición
  document.querySelectorAll('.song-card').forEach((c, idx) => {
    c.classList.toggle('active', idx === songId);
  });

  // Actualizar Carátula y Troquelado en Vista Escenario
  let preset = {
    text1: state.SONG.title,
    text2: state.SONG.artist,
    bg: state.SONG.cover ? `url('${state.SONG.cover}')` : 'linear-gradient(135deg, #221E19 0%, #110F0D 100%)',
    bgPos: 'center center',
    keyIndex: 0
  };
  if (!state.SONG.backendStems && state.SONG_HERO_PRESETS[songId]) {
     preset = state.SONG_HERO_PRESETS[songId];
  }

  const t1 = document.getElementById('stencilText1');
  const t2 = document.getElementById('stencilText2');
  const o1 = document.getElementById('stencilOutline1');
  const o2 = document.getElementById('stencilOutline2');
  const art = document.getElementById('heroArtFull');
  const keyB = document.getElementById('heroKeyBadge');

  if (t1) t1.textContent = preset.text1;
  if (t2) t2.textContent = preset.text2;
  if (o1) o1.textContent = preset.text1;
  if (o2) o2.textContent = preset.text2;
  if (art) {
    art.style.backgroundImage = preset.bg;
    art.style.backgroundPosition = preset.bgPos;
  }
  if (keyB) {
    const currentKey = state.transposeTargetKey || getSongRootKey(state.SONG.key || 'C');
    const currentLabel = keyB.querySelector('#heroKeyCurrent');
    if (currentLabel) currentLabel.textContent = currentKey;
    else keyB.textContent = currentKey;
    keyB.classList.toggle('transposed', state.transposeSemitones !== 0);
    keyB.title = state.transposeSemitones === 0
      ? `Tonalidad original: ${formatMusicalKey(state.SONG.key || 'C')}. Pulsa para transponer.`
      : `Original: ${formatMusicalKey(state.SONG.key || 'C')} · Sonando: ${currentKey}. Pulsa para cambiar.`;
    keyB.setAttribute('aria-label', `Tonalidad actual ${currentKey}. Original ${formatMusicalKey(state.SONG.key || 'C')}. Cambiar transposición`);
  }

  if (state.padFollowSetlist) {
    state.currentPadKeyIndex = getKeyNoteIndex(state.SONG.key);
    state.currentPadKeyName = formatPadNote(state.SONG.key);
  }
  if (state.isContinuousPadPlaying) {
    startPad(state.currentPadKeyIndex, state.currentPadKeyName);
  } else {
    updatePadRadioUI();
  }

  // Stems de la canción
  state.stemKeys = orderMixerStemKeys(state.SONG.stems ? [...state.SONG.stems] : []);
  if (state.SONG && state.SONG.backendStems) {
    state.SONG.backendStems.forEach(s => {
      if (!state.STEMS[s.id]) {
         state.STEMS[s.id] = { label: s.label, gain: s.gain || 0.75, def: s.gain || 0.75, type: s.category || 'other', muted: false, solo: false, node: null, ana: null, lvl: 0 };
      } else {
         state.STEMS[s.id].label = s.label; state.STEMS[s.id].type = s.category;
      }
    });
  }
  state.stemKeys.forEach(ensureStemAudioNode);

  // Actualizar cabecera de consola en vista edición
  const titleEl = state.$('#cSongTitle');
  if (titleEl) titleEl.textContent = state.SONG.title;
  const metaEl = state.$('#cSongMeta');
  if (metaEl) metaEl.textContent = state.SONG.artist || '';
  const bpmEl = state.$('#bpmDisp');
  if (bpmEl) bpmEl.textContent = state.bpm.toFixed(1);

  // Refrescar vistas y controles
  updateStemCountBadge();
  renderTimeline(); syncModernUI(0);
  renderMixer();
  renderStageSections();
  state.renderNextSongsQueue();
  syncChannels();
  applyMix();
  say('CANCIÓN → ' + state.SONG.title + ' (' + state.stemKeys.length + ' STEMS)');
  return loadRealStems(state.SONG);
}


/* ---------- Renderizado Dinámico y Reordenamiento de Setlist (Vista Edición) ---------- */

export function renderEditionSongList() {
  const listEl = document.getElementById('editionSongItemsList');
  if (!listEl) return;

  if (state.SONGS_DATA.length === 0) {
    const curName = state.ALL_SETLISTS[state.currentSetlistIdx].name;
    listEl.innerHTML = `
      <div style="padding: 12px 18px; font-family: var(--mono); font-size: 11px; font-weight: 800; color: var(--amber); letter-spacing: 0.1em; border-top: 1px solid var(--line); margin-top: 5px;">
        ${curName}
      </div>
      <div style="padding:20px;text-align:center;color:var(--mut);font-family:var(--mono);font-size:11px;">
        El setlist está vacío.<br><br>Sube tus multitracks con el botón + AGREGAR.
      </div>
    `;
    const emtSongCount = document.getElementById('emtSongCount');
    if (emtSongCount) emtSongCount.textContent = 0;
    return;
  }

  let html = '';
  for (let i = 0; i < state.SONGS_DATA.length; i++) {
    const s = state.SONGS_DATA[i];
    const isActive = (i === state.currentSongIdx);
    const isFirst = (i === 0);
    const isLast = (i === state.SONGS_DATA.length - 1);

    html += `
      <div class="song-card ${isActive ? 'active' : ''}" data-song="${i}">
        <div class="sc-reorder-col" title="Subir o bajar posición en la lista">
          <div class="sc-step-btns">
            <button type="button" class="sc-step-btn btn-up" data-act="up" data-idx="${i}" title="Subir posición" ${isFirst ? 'disabled' : ''}>▲</button>
            <button type="button" class="sc-step-btn btn-down" data-act="down" data-idx="${i}" title="Bajar posición" ${isLast ? 'disabled' : ''}>▼</button>
          </div>
        </div>
        <div class="sc-main-info">
          <div class="sc-row-top">
            <strong class="sc-title-text"><span class="sc-order-num">${i + 1}.</span> ${s.title}</strong>
            <button type="button" class="sc-key-pill ${s.transposeKey ? 'transposed' : ''}" data-song-index="${i}" title="Original: ${formatMusicalKey(s.key || 'C')} · Sonando: ${s.transposeKey || getSongRootKey(s.key || 'C')}">
              <span class="sc-key-current">${s.transposeKey || getSongRootKey(s.key || 'C')}</span>
            </button>
          </div>
          <div class="sc-row-meta">
            <span>${s.bpm} BPM</span>
            <span>4/4</span>
            <button type="button" class="sc-remove" aria-label="Quitar canción de la setlist" title="Quitar de la setlist">×</button>
          </div>
        </div>
      </div>
      ${isLast ? '' : `
        <div class="sc-transition" data-transition-index="${i}">
          <button type="button" class="sc-transition-trigger" aria-expanded="false"
            aria-controls="sc-transition-${i}" aria-label="${transitionLabel(i, getSongTransition(s))}"
            title="${transitionLabels[getSongTransition(s)]}">${transitionIcons[getSongTransition(s)]}</button>
          <div class="sc-transition-options" id="sc-transition-${i}" role="group" aria-label="Tipo de transición" hidden>
            ${Object.entries(transitionLabels).map(([mode, label]) =>
              `<button type="button" data-transition-mode="${mode}" aria-pressed="${getSongTransition(s) === mode}">
                <span aria-hidden="true">${transitionIcons[mode]}</span> ${label}
              </button>`
            ).join('')}
          </div>
        </div>
      `}
    `;
  }
  listEl.innerHTML = html;
  const emtSongCount = document.getElementById('emtSongCount');
  if (emtSongCount) emtSongCount.textContent = state.SONGS_DATA.length;
  bindEditionSongListEvents();
}



export function bindEditionSongListEvents() {
  const listEl = document.getElementById('editionSongItemsList');
  if (!listEl) return;
  listEl.querySelectorAll('[data-transition-index]').forEach(control => {
    const index = Number(control.dataset.transitionIndex);
    const trigger = control.querySelector('.sc-transition-trigger');
    const options = control.querySelector('.sc-transition-options');
    const buttons = [...options.querySelectorAll('button')];
    function setOpen(open) {
      options.hidden = !open;
      trigger.setAttribute('aria-expanded', String(open));
    }
    trigger.addEventListener('click', () => setOpen(options.hidden));
    control.addEventListener('focusout', event => {
      if (!control.contains(event.relatedTarget)) setOpen(false);
    });
    control.addEventListener('keydown', event => {
      if (event.key !== 'Escape' || options.hidden) return;
      event.stopPropagation();
      trigger.focus();
      setOpen(false);
    });
    buttons.forEach(button => {
      button.addEventListener('click', () => {
        const song = state.SONGS_DATA[index];
        if (!song) return;
        const mode = button.dataset.transitionMode;
        song.transition = mode;
        trigger.textContent = transitionIcons[mode];
        trigger.title = transitionLabels[mode];
        trigger.setAttribute('aria-label', transitionLabel(index, mode));
        buttons.forEach(option => option.setAttribute('aria-pressed', String(option === button)));
        trigger.focus();
        setOpen(false);
        renderStageSlider();
        say('TRANSICIÓN ACTUALIZADA · USA GUARDAR PARA CONSERVARLA');
      });
    });
  });


  const cards = listEl.querySelectorAll('.song-card');

  cards.forEach(card => {
    const idx = +card.dataset.song;

    // Clic en la tarjeta selecciona la canción
    card.addEventListener('click', (e) => {
      if (e.target.closest('.sc-step-btn') || e.target.closest('.sc-reorder-col') || e.target.closest('.sc-key-pill')) return;
      selectSong(idx);
    });

    card.querySelector('.sc-remove')?.addEventListener('click', async (e) => {
      e.stopPropagation();
      const song = state.SONGS_DATA[idx];
      if (!window.CURRENT_USER) { openAuthModal('login'); return; }
      if (!song || !confirm(`¿Quitar «${song.title}» de esta setlist?`)) return;
      const wasActive = idx === state.currentSongIdx;
      state.SONGS_DATA.splice(idx, 1);
      if (wasActive && state.SONGS_DATA.length) {
        selectSong(Math.min(idx, state.SONGS_DATA.length - 1));
      } else if (wasActive) {
        state.currentLoadSession++;
        state.audioLoading = false;
        state.REAL_STEM_BUFFERS = {};
        switchSetlist(state.currentSetlistIdx);
      } else if (idx < state.currentSongIdx) {
        state.currentSongIdx--;
      }
      renderEditionSongList();
      renderStageSlider();
      state.renderNextSongsQueue();
      await saveCurrentSetlist();
    });

    card.querySelector('.sc-key-pill')?.addEventListener('click', (e) => {
      e.stopPropagation();
      if (idx !== state.currentSongIdx) selectSong(idx);
      openTransposePicker();
    });

    // Botones de paso ▲ y ▼
    card.querySelectorAll('.sc-step-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const act = btn.dataset.act;
        const targetIdx = act === 'up' ? idx - 1 : idx + 1;
        reorderSong(idx, targetIdx);
      });
    });
  });
}



export function reorderSong(fromIdx, toIdx) {
  if (fromIdx === toIdx || fromIdx < 0 || toIdx < 0 || fromIdx >= state.SONGS_DATA.length || toIdx >= state.SONGS_DATA.length) return;

  const activeSong = state.SONGS_DATA[state.currentSongIdx];

  // Reordenar en el array SONGS_DATA
  const [movedSong] = state.SONGS_DATA.splice(fromIdx, 1);
  state.SONGS_DATA.splice(toIdx, 0, movedSong);

  // Mantener la selección apuntando a la canción activa
  state.currentSongIdx = state.SONGS_DATA.indexOf(activeSong);
  state.SONG = state.SONGS_DATA[state.currentSongIdx];

  // Re-renderizar lista en vista de Edición
  renderEditionSongList();

  // Re-renderizar carrusel en vista de Show (sincronización en vivo)
  renderStageSlider();

  // Actualizar pad y puente de tonalidad
  updatePadRadioUI();

  say(`SETLIST REORDENADO: "${movedSong.title}" AHORA ES #${toIdx + 1}`);
}


/* ==========================================================================
   GESTIÓN Y CONMUTACIÓN DE SETLISTS (CAMBIAR Y CREAR NUEVAS LISTAS)
   ========================================================================== */

export function getSetlistStorageKey() {
  const user = window.CURRENT_USER;
  if (!user) return null;
  if (user.role === 'admin') return 'pulso_saved_setlists_admin';
  if (user.grupo_id && user.grupo_id !== 'default') {
    return `pulso_saved_setlists_group_${user.grupo_id}`;
  }
  return `pulso_saved_setlists_user_${user.id}`;
}



export function renderSetlistModalCards() {
  const container = document.getElementById('setlistCardsContainer');
  if (!container) return;

  if (!window.CURRENT_USER) {
    container.innerHTML = `
      <div style="text-align:center; padding:24px 16px; border:1px dashed var(--line2); border-radius:10px; color:var(--mut);">
        <p style="margin:0 0 10px; font-size:12px; font-weight:700; color:var(--ink);">Modo Invitado (Sin sesión activa)</p>
        <p style="margin:0 0 14px; font-size:11px;">Inicia sesión en tu cuenta para cargar las setlists y canciones de tu grupo.</p>
        <button type="button" class="btn btn-amber btn-sm" onclick="closeSetlistModal(); openAuthModal('login');">INICIAR SESIÓN</button>
      </div>
    `;
    return;
  }

  const isAdmin = window.CURRENT_USER.role === 'admin';
  let html = '';
  for (let i = 0; i < state.ALL_SETLISTS.length; i++) {
    const sl = state.ALL_SETLISTS[i];
    const isActive = (i === state.currentSetlistIdx);
    const groupTag = isAdmin
      ? `<span class="role-badge ${sl.group_id ? 'user' : 'admin'}" style="margin-left:6px; font-size:9px;">${sl.group_name || sl.group_id || 'GLOBAL'}</span>`
      : (sl.group_name ? `<span class="role-badge user" style="margin-left:6px; font-size:9px;">${sl.group_name}</span>` : '');
    html += `
      <div class="setlist-card-item ${isActive ? 'active' : ''}" data-sidx="${i}" title="Activar ${sl.name}">
        <div class="sci-info">
          <strong class="sci-title" style="display:flex; align-items:center; flex-wrap:wrap; gap:4px;">${sl.name} ${groupTag}</strong>
          <span class="sci-meta">${sl.description || 'Setlist'} · ${(sl.songs || []).length} canciones</span>
        </div>
        <div class="sci-right">
          ${isActive ? '<span class="sci-active-badge">EN VIVO</span>' : ''}
          <span class="sci-count-badge">${(sl.songs || []).length} TEMAS</span>
        </div>
      </div>
    `;
  }
  container.innerHTML = html;

  container.querySelectorAll('.setlist-card-item').forEach(card => {
    card.addEventListener('click', () => {
      const sidx = +card.dataset.sidx;
      switchSetlist(sidx);
    });
  });
}



export function openSetlistModal() {
  if (!window.CURRENT_USER) {
    openAuthModal('login');
    if (typeof say === 'function') say('INICIA SESIÓN PARA GESTIONAR LAS SETLISTS DE TU GRUPO');
    return;
  }
  const modal = document.getElementById('setlistModal');
  if (!modal) return;
  renderSetlistModalCards();
  modal.classList.add('open');
  setTimeout(() => lucide.createIcons(), 20);
  const input = document.getElementById('newSetlistInput');
  if (input) {
    input.value = '';
    setTimeout(() => input.focus(), 80);
  }
}



export function closeSetlistModal() {
  const modal = document.getElementById('setlistModal');
  if (modal) modal.classList.remove('open');
}



export function switchSetlist(setlistIdx) {
  if (setlistIdx < 0 || setlistIdx >= state.ALL_SETLISTS.length) return;
  state.currentSetlistIdx = setlistIdx;
  state.SONGS_DATA = state.ALL_SETLISTS[state.currentSetlistIdx].songs || [];
  state.currentSongIdx = 0;
  state.SONG = state.SONGS_DATA[0] || null;
  resetTransposeForCurrentSong();
  state.bpm = state.SONG ? state.SONG.bpm : 120;
  state.stemKeys = state.SONG && state.SONG.stems ? [...state.SONG.stems] : [];
  
  if (state.SONG && state.SONG.backendStems) {
    state.SONG.backendStems.forEach(s => {
      if (!state.STEMS[s.id]) {
         state.STEMS[s.id] = { label: s.label, gain: s.gain || 0.75, def: s.gain || 0.75, type: s.category || 'other', muted: false, solo: false, node: null, ana: null, lvl: 0 };
      } else {
         state.STEMS[s.id].label = s.label; state.STEMS[s.id].type = s.category;
      }
    });
  }
  state.stemKeys = orderMixerStemKeys(state.stemKeys);

  // Actualizar nombres mostrados en Show y en Edición
  const curName = state.ALL_SETLISTS[state.currentSetlistIdx].name;
  const showNameEl = document.getElementById('showSetlistName');
  const editionNameEl = document.getElementById('editionSetlistName');
  if (showNameEl) showNameEl.textContent = curName;
  if (editionNameEl) editionNameEl.textContent = curName;

  // Actualizar contador en Show
  const countEl = document.getElementById('stageSliderCount');
  if (countEl) countEl.textContent = `${state.SONGS_DATA.length} CANCIONES`;

  // Refrescar vistas completas
  updateStemCountBadge();
  renderEditionSongList();
  renderStageSlider();
  renderTimeline(); syncModernUI(0);
  renderMixer();
  renderStageSections();
  state.renderNextSongsQueue();
  drawHeroWaveform();
  drawStageStereoMeter();
  updatePadRadioUI();
  centerSliderOnActiveSong();
  syncChannels();
  applyMix();
  stopAll();
  
  if (state.SONG && (state.SONG.backendStems || state.SONG.downloadUrl || state.SONG.folderId)) {
    loadRealStems(state.SONG);
  }

  // Cerrar modal
  closeSetlistModal();
  setTimeout(() => lucide.createIcons(), 30);
  say(`SETLIST ACTIVADA: "${curName}" (${state.SONGS_DATA.length} TEMAS)`);
}



export function createNewSetlist(name) {
  if (!window.CURRENT_USER) {
    closeSetlistModal();
    openAuthModal('login');
    say('INICIA SESIÓN PARA CREAR SETLISTS DE TU GRUPO');
    return;
  }
  const cleanName = (name || '').trim().toUpperCase();
  if (!cleanName) {
    say('INTRODUCE UN NOMBRE PARA LA SETLIST');
    return;
  }

  const user = window.CURRENT_USER;
  // Generar nueva setlist iniciando vacía y asociada al grupo del usuario
  const newSetlist = {
    id: 'setlist-' + Date.now(),
    name: cleanName,
    description: user.group_name ? `Grupo: ${user.group_name}` : 'Creada recientemente',
    group_id: user.role === 'admin' ? null : user.grupo_id,
    group_name: user.group_name || null,
    songs: []
  };

  state.ALL_SETLISTS.push(newSetlist);
  switchSetlist(state.ALL_SETLISTS.length - 1);
  saveCurrentSetlist();
  say(`NUEVA SETLIST CREADA: "${cleanName}"`);
}



export async function saveCurrentSetlist(e) {
  if (e) e.stopPropagation();
  if (!window.CURRENT_USER) {
    openAuthModal('login');
    say('INICIA SESIÓN PARA GUARDAR SETLISTS');
    return;
  }
  const btnModal = document.getElementById('btnSaveSetlistModal');
  const btnShow = document.getElementById('btnSaveSetlistShow');
  const btnEdit = document.getElementById('btnSaveSetlistEdition');
  const btns = [btnModal, btnShow, btnEdit].filter(Boolean);

  btns.forEach(b => {
    b.innerHTML = '<i data-lucide="loader-2" style="width:13px;height:13px;animation:spin 1s linear infinite;"></i><span>GUARDANDO...</span>';
    b.style.pointerEvents = 'none';
  });
  if (window.lucide) lucide.createIcons();

  let saved = false;
  // 1. Guardar en backend local (/api/setlists)
  try {
    const res = await fetch('/api/setlists', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${getAuthToken()}` },
      body: JSON.stringify(state.ALL_SETLISTS)
    });
    if (res.ok) {
      saved = true;
      console.log("Setlists guardadas en el backend con éxito");
    }
  } catch (err) {
    console.warn("Backend no disponible, guardando en localStorage:", err);
  }

  // 2. Guardar en localStorage aislado por grupo como respaldo
  const storageKey = getSetlistStorageKey();
  if (storageKey) {
    try {
      localStorage.setItem(storageKey, JSON.stringify(state.ALL_SETLISTS));
    } catch (_) {}
  }

  if (!saved) {
    btns.forEach(b => {
      b.textContent = 'Guardar';
      b.style.pointerEvents = 'auto';
    });
    say('NO SE PUDO GUARDAR EN EL SERVIDOR');
    return false;
  }

  // Feedback visual en botones
  setTimeout(() => {
    btns.forEach(b => {
      b.innerHTML = '<i data-lucide="check" style="width:13px;height:13px;"></i><span>GUARDADO</span>';
      b.style.color = '#000';
      b.style.backgroundColor = '#43B97C';
      b.style.borderColor = '#43B97C';
      b.style.pointerEvents = 'auto';
    });
    if (window.lucide) lucide.createIcons();

    const curName = state.ALL_SETLISTS[state.currentSetlistIdx] ? state.ALL_SETLISTS[state.currentSetlistIdx].name : 'SETLIST';
    say(`SETLIST "${curName}" GUARDADA (${state.SONGS_DATA.length} TEMAS)`);
    renderSetlistModalCards();

    setTimeout(() => {
      btns.forEach(b => {
        b.innerHTML = '<i data-lucide="save" style="width:13px;height:13px;"></i><span>GUARDAR</span>';
        b.style.color = '';
        b.style.backgroundColor = '';
        b.style.borderColor = '';
      });
      if (window.lucide) lucide.createIcons();
    }, 2000);
  }, 350);
  return true;
}

export function initializeSetlists() {


/* ---------- Configuración Visual de Temas en Vista Escenario ---------- */
state.SONG_HERO_PRESETS = [
  {
    text1: 'TU PRESENCIA',
    text2: 'ES EL CIELO',
    bg: "url('assets/214.jpg')",
    bgPos: 'center 30%',
    keyIndex: 4 // E
  },
  {
    text1: 'REY DE REYES',
    text2: 'HILLSONG',
    bg: 'radial-gradient(circle at 70% 30%, rgba(67, 185, 124, 0.9) 0%, transparent 60%), linear-gradient(135deg, #09201a 0%, #173628 50%, #06110d 100%)',
    bgPos: 'center center',
    keyIndex: 2 // D
  },
  {
    text1: 'LA BONDAD',
    text2: 'DE DIOS',
    bg: 'radial-gradient(circle at 65% 35%, rgba(233, 162, 59, 0.85) 0%, transparent 60%), linear-gradient(135deg, #231604 0%, #3d2407 50%, #0c0803 100%)',
    bgPos: 'center center',
    keyIndex: 7 // G
  },
  {
    text1: 'TUMBAS A',
    text2: 'JARDINES',
    bg: 'radial-gradient(circle at 70% 30%, rgba(139, 92, 246, 0.85) 0%, transparent 60%), linear-gradient(135deg, #180d2b 0%, #2b144d 50%, #090512 100%)',
    bgPos: 'center center',
    keyIndex: 11 // B
  },
  {
    text1: 'GRANDE Y',
    text2: 'FUERTE',
    bg: 'radial-gradient(circle at 65% 30%, rgba(228, 96, 78, 0.85) 0%, transparent 60%), linear-gradient(135deg, #290808 0%, #441111 50%, #0d0303 100%)',
    bgPos: 'center center',
    keyIndex: 9 // Am
  }
];


/* ---------- Cola de Siguientes Canciones en Vivo & Transiciones ---------- */

state.TRANSITION_MODES = {
  pad: {
    label: 'PAD AMBIENTE',
    icon: 'waves',
    class: 'mode-pad',
    desc: 'Mantiene colchón de acordes continuo entre canciones'
  },
  overlap: {
    label: 'TRASLAPE',
    icon: 'waves',
    class: 'mode-pad',
    desc: 'La siguiente canción entra durante el fundido de la anterior'
  },
  instant: {
    label: 'AL TERMINAR',
    icon: 'zap',
    class: 'mode-instant',
    desc: 'Cambio inmediato sin interrupción'
  },
  stop: {
    label: 'CON PAUSA',
    icon: 'pause-circle',
    class: 'mode-stop',
    desc: 'Pausa en espera de la señal del director'
  }
};


// Alias para compatibilidad con llamadas existentes
state.renderNextSongsQueue = renderStageSlider;


// Navegación con flechas < y > del carrusel (desliza y centra canción)
state.ssnPrev = document.getElementById('stageSliderPrev');

state.ssnNext = document.getElementById('stageSliderNext');

if (state.ssnPrev) {
  state.ssnPrev.addEventListener('click', () => {
    if (state.currentSongIdx > 0) {
      const transMode = getSongTransition(state.SONGS_DATA[state.currentSongIdx - 1]);
      executeTransitionToSong(state.currentSongIdx - 1, transMode);
    } else {
      centerSliderOnActiveSong();
    }
  });
}

if (state.ssnNext) {
  state.ssnNext.addEventListener('click', () => {
    if (state.currentSongIdx < state.SONGS_DATA.length - 1) {
      const transMode = getSongTransition(state.SONG);
      executeTransitionToSong(state.currentSongIdx + 1, transMode);
    } else {
      centerSliderOnActiveSong();
    }
  });
}


// Scroll horizontal por arrastre fluido y rueda del ratón en el carrusel
state.ssnViewport = document.getElementById('stageSliderViewport');

if (state.ssnViewport) {
  let isDragging = false;
  let startX = 0;
  let startScrollLeft = 0;

  state.ssnViewport.addEventListener('mousedown', (e) => {
    if (e.target.closest('button, .slider-trans-btn')) return;
    isDragging = true;
    state.ssnViewport.classList.add('grabbing');
    startX = e.pageX - state.ssnViewport.offsetLeft;
    startScrollLeft = state.ssnViewport.scrollLeft;
  });

  window.addEventListener('mouseup', () => {
    if (isDragging) {
      isDragging = false;
      state.ssnViewport.classList.remove('grabbing');
    }
  });

  window.addEventListener('mouseleave', () => {
    if (isDragging) {
      isDragging = false;
      state.ssnViewport.classList.remove('grabbing');
    }
  });

  state.ssnViewport.addEventListener('mousemove', (e) => {
    if (!isDragging) return;
    e.preventDefault();
    const x = e.pageX - state.ssnViewport.offsetLeft;
    const walk = (x - startX) * 1.5;
    state.ssnViewport.scrollLeft = startScrollLeft - walk;
  });

  state.ssnViewport.addEventListener('wheel', (e) => {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) {
      e.preventDefault();
      state.ssnViewport.scrollLeft += e.deltaY;
    }
  }, { passive: false });
}

window.saveCurrentSetlist = saveCurrentSetlist;


// Botones y Eventos del Selector de Setlists
state.btnSelectSetlistShow = document.getElementById('btnSelectSetlistShow');

state.btnSelectSetlistEdition = document.getElementById('btnSelectSetlistEdition');

state.setlistModal = document.getElementById('setlistModal');

state.closeSetlistModalBtn = document.getElementById('closeSetlistModalBtn');

state.btnCreateNewSetlist = document.getElementById('btnCreateNewSetlist');

state.newSetlistInput = document.getElementById('newSetlistInput');


if (state.btnSelectSetlistShow) state.btnSelectSetlistShow.addEventListener('click', openSetlistModal);

if (state.btnSelectSetlistEdition) state.btnSelectSetlistEdition.addEventListener('click', openSetlistModal);

if (state.closeSetlistModalBtn) state.closeSetlistModalBtn.addEventListener('click', closeSetlistModal);

if (state.setlistModal) {
  state.setlistModal.addEventListener('click', (e) => {
    if (e.target === state.setlistModal) closeSetlistModal();
  });
}

if (state.btnCreateNewSetlist) {
  state.btnCreateNewSetlist.addEventListener('click', () => {
    if (state.newSetlistInput) createNewSetlist(state.newSetlistInput.value);
  });
}

if (state.newSetlistInput) {
  state.newSetlistInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      createNewSetlist(state.newSetlistInput.value);
    }
  });
}


// Selector de Vistas (Escenario vs Edición)
document.getElementById('btnViewEdition').addEventListener('click', () => {
  document.getElementById('btnViewEdition').classList.add('active');
  document.getElementById('btnViewShow').classList.remove('active');
  document.getElementById('viewEdition').classList.add('active');
  document.getElementById('sidebarAccountSlot').appendChild(document.getElementById('userMenuWrapper'));
  document.getElementById('viewShow').classList.remove('active');
  setTimeout(() => {
    drawWaveAll();
    lucide.createIcons();
  }, 50);
});


document.getElementById('btnViewShow').addEventListener('click', () => {
  document.getElementById('btnViewShow').classList.add('active');
  document.getElementById('btnViewEdition').classList.remove('active');
  document.getElementById('viewShow').classList.add('active');
  document.getElementById('headerAccountSlot').appendChild(document.getElementById('userMenuWrapper'));
  document.getElementById('viewEdition').classList.remove('active');
  setTimeout(() => {
    drawHeroWaveform();
    drawStageStereoMeter();
    renderStageSections();
    state.renderNextSongsQueue();
    centerSliderOnActiveSong();
    updatePadRadioUI();
  }, 50);
});


// Modales de Canciones: Servidor vs Local
state.uploadModal = document.getElementById('uploadModal');

state.openUploadBtn = document.getElementById('openUploadBtn');

state.closeModalBtn = document.getElementById('closeModalBtn');

state.btnSidebarAddSong = document.getElementById('btnSidebarAddSong');

state.addSongChoiceModal = document.getElementById('addSongChoiceModal');

state.closeAddChoiceBtn = document.getElementById('closeAddChoiceBtn');


if (state.openUploadBtn) state.openUploadBtn.addEventListener('click', openServerUploadWizard);

if (state.btnSidebarAddSong) state.btnSidebarAddSong.addEventListener('click', openAddSongChoiceModal);

if (state.closeModalBtn && state.uploadModal) state.closeModalBtn.addEventListener('click', () => state.uploadModal.classList.remove('open'));

if (state.closeAddChoiceBtn && state.addSongChoiceModal) state.closeAddChoiceBtn.addEventListener('click', () => state.addSongChoiceModal.classList.remove('open'));

if (state.addSongChoiceModal) {
  state.addSongChoiceModal.addEventListener('click', (e) => {
    if (e.target === state.addSongChoiceModal) state.addSongChoiceModal.classList.remove('open');
  });
}


// Resize Listeners
window.addEventListener('resize', () => {
  drawWaveAll();
  renderStageSlider(); // Ensure stage slider scales perfectly
  drawHeroWaveform();
  drawStageStereoMeter();
  centerSliderOnActiveSong();
  updatePadRadioUI();
});


// Inicialización
renderEditionSongList();

updateStemCountBadge();

renderMixer();

renderTimeline();
 syncModernUI(0);

renderStageSections();

state.renderNextSongsQueue();

drawHeroWaveform();

drawStageStereoMeter();

updatePadRadioUI();

syncChannels();

window.addEventListener('load', () => {
  drawWaveAll();
  drawHeroWaveform();
  drawStageStereoMeter();
  renderStageSections();
  state.renderNextSongsQueue();
  centerSliderOnActiveSong();
  updatePadRadioUI();
});

setTimeout(() => {
  drawWaveAll();
  drawHeroWaveform();
  drawStageStereoMeter();
  renderStageSections();
  state.renderNextSongsQueue();
  centerSliderOnActiveSong();
  updatePadRadioUI();
}, 100);

lucide.createIcons();


// Native Mobile Platform Live Integration (Capacitor)
document.addEventListener('DOMContentLoaded', async () => {
  // Wheel Zoom en el timeline
  const tlCont = document.getElementById('timelineContainer');
  if (tlCont) {
    tlCont.addEventListener('wheel', (e) => {
      if (!state.SONG) return;
      if (Math.abs(e.deltaY) > 0) {
        e.preventDefault();
        const zoomDelta = e.deltaY < 0 ? 1.1 : 0.9;
        const oldZoom = state.tlZoom;
        state.tlZoom = Math.max(1.0, Math.min(20.0, state.tlZoom * zoomDelta));
        if (oldZoom !== state.tlZoom) {
          const rect = tlCont.getBoundingClientRect();
          const mouseX = e.clientX - rect.left;
          const scrollPct = (tlCont.scrollLeft + mouseX) / (rect.width * oldZoom);
          renderTimeline(); syncModernUI(0);
          tlCont.scrollLeft = (scrollPct * rect.width * state.tlZoom) - mouseX;
        }
      }
    }, { passive: false });
  }

  // Drag & Drop de Arranger
  const labels = document.querySelectorAll('.arranger-label');
  labels.forEach(l => {
    l.addEventListener('dragstart', (e) => {
      let name = l.dataset.name;
      if (name === 'OTRO') {
        const customInput = document.getElementById('arrangerCustomName');
        if (customInput && customInput.value.trim()) {
          name = customInput.value.trim().toUpperCase();
        }
      }
      e.dataTransfer.setData('text/plain', name);
      e.dataTransfer.effectAllowed = 'copy';
      l.style.opacity = '0.5';
      setTimeout(() => {
        const p = document.getElementById('arrangerPanel');
        if (p) p.classList.remove('active');
      }, 10);
    });
    l.addEventListener('dragend', (e) => {
      l.style.opacity = '1';
    });
  });

  const tlBand = document.getElementById('tlBand');
  
  document.addEventListener('pointerdown', (e) => {
    if (typeof state.selectedSectionIdx !== 'undefined' && state.selectedSectionIdx !== -1) {
      if (!e.target.closest('.tl-sec') && !e.target.closest('#arrangerPanel') && !e.target.closest('#btnArranger')) {
        state.selectedSectionIdx = -1;
        renderTimeline(); syncModernUI(0);
      }
    }
    const p = document.getElementById('arrangerPanel');
    if (p && p.classList.contains('active')) {
      if (!e.target.closest('#arrangerPanel') && !e.target.closest('#btnArranger')) {
        p.classList.remove('active');
      }
    }
  });

  if (tlBand) {
    tlBand.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = 'copy';
      if (!state.SONG) return;
      
      const rect = tlBand.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const pct = Math.max(0, Math.min(1, x / rect.width));
      const totBars = Math.ceil((state.SONG.total16ths || 128) / 16);
      const hoverBar = Math.round(pct * totBars);
      
      let ghost = document.getElementById('dragGhost');
      if (!ghost) {
         ghost = document.createElement('div');
         ghost.id = 'dragGhost';
         ghost.style.cssText = 'position:absolute; height:100%; background:rgba(255,255,255,0.1); border:1px dashed rgba(255,255,255,0.5); pointer-events:none; top:0; z-index:5; border-radius:4px;';
         tlBand.appendChild(ghost);
      }
      ghost.style.display = 'block';
      const pLeft = (hoverBar / totBars) * 100;
      const pWidth = (4 / totBars) * 100;
      ghost.style.left = `${pLeft}%`;
      ghost.style.width = `${pWidth}%`;
    });
    
    tlBand.addEventListener('dragleave', (e) => {
      const ghost = document.getElementById('dragGhost');
      if (ghost) ghost.style.display = 'none';
    });

    tlBand.addEventListener('drop', async (e) => {
      e.preventDefault();
      const ghost = document.getElementById('dragGhost');
      if (ghost) ghost.style.display = 'none';
      if (!state.SONG) return;
      const name = e.dataTransfer.getData('text/plain');
      if (name) {
        const rect = tlBand.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const pct = Math.max(0, Math.min(1, x / rect.width));
        const totBars = Math.ceil((state.SONG.total16ths || 128) / 16);
        const dropBar = Math.round(pct * totBars);
        if (!state.SONG.sections) state.SONG.sections = [];
        state.SONG.sections.push({ name, bar: dropBar, len: 4 });
        renderTimeline(); syncModernUI(0);
        renderStageSections();
        await saveSections();
      }
    });
  }

  if (window.Capacitor) {
    try {
      const { ScreenOrientation } = window.Capacitor.Plugins || {};
      if (ScreenOrientation) {
        await ScreenOrientation.lock({ orientation: 'landscape' });
      }
    } catch (_) {}
    try {
      const { KeepAwake } = window.Capacitor.Plugins || {};
      if (KeepAwake) {
        await KeepAwake.keepAwake();
      }
    } catch (_) {}
  }
});
}

