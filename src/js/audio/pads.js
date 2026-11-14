import { state } from '../state/store.js';
import { getAudioCtx } from './engine.js';
import { say } from '../ui/show.js';



export function formatMusicalKey(key) {
  const value = String(key || 'C').trim();
  return value ? value.charAt(0).toUpperCase() + value.slice(1).toLowerCase() : 'C';
}



export function formatPadNote(key) {
  const formatted = formatMusicalKey(key);
  return formatted === 'Bb' ? 'A#' : formatted;
}



export function getFullToneName(key) {
  const map = {
    'C': 'Do mayor', 'C#': 'Do sostenido mayor', 'Db': 'Re bemol mayor',
    'D': 'Re mayor', 'D#': 'Re sostenido mayor', 'Eb': 'Mi bemol mayor',
    'E': 'Mi mayor', 'F': 'Fa mayor', 'F#': 'Fa sostenido mayor', 'Gb': 'Sol bemol mayor',
    'G': 'Sol mayor', 'G#': 'Sol sostenido mayor', 'Ab': 'La bemol mayor',
    'A': 'La mayor', 'A#': 'La sostenido mayor', 'Bb': 'Si bemol mayor',
    'B': 'Si mayor'
  };
  const formattedKey = formatMusicalKey(key);
  return map[formattedKey] || `${formattedKey} mayor`;
}



export function getKeyNoteIndex(key) {
  const clean = (key || 'C').toUpperCase().trim();
  const map = {
    'C': 0, 'C#': 1, 'DB': 1,
    'D': 2, 'D#': 3, 'EB': 3,
    'E': 4,
    'F': 5, 'F#': 6, 'GB': 6,
    'G': 7, 'G#': 8, 'AB': 8,
    'A': 9, 'A#': 10, 'BB': 10,
    'B': 11
  };
  return map[clean] !== undefined ? map[clean] : 0;
}



export function getSongRootKey(key) {
  const match = String(key || 'C').trim().match(/^([A-Ga-g])([#b]?)/);
  return formatPadNote(match ? match[0] : 'C');
}



const recordedPads = new Map();
let padRequest = 0;
let recordedSource;

export function startPad(k, keyName) {
  const c = getAudioCtx();
  if (c.state === 'suspended') c.resume().catch(() => {});
  stopPad();
  if (k !== undefined) {
    state.currentPadKeyIndex = k;
    state.currentPadKeyName = formatPadNote(keyName || state.RADIO_NOTES[k]?.name || 'C');
  }
  const voice = document.getElementById('moPadVoice')?.value || 'mi';
  const request = padRequest;
  state.isContinuousPadPlaying = true;
  updatePadRadioUI();
  if (!recordedPads.has(voice)) {
    recordedPads.set(voice, fetch(new URL(`../../assets/pads/${voice}.flac`, import.meta.url))
      .then(response => {
        if (!response.ok) throw new Error('No se pudo cargar el PAD');
        return response.arrayBuffer();
      }).then(bytes => c.decodeAudioData(bytes)).catch(error => {
        recordedPads.delete(voice);
        throw error;
      }));
  }
  recordedPads.get(voice).then(buffer => {
    if (request !== padRequest) return;
    const source = recordedSource = c.createBufferSource();
    const gain = state.padGain = c.createGain();
    const semitones = (getKeyNoteIndex(state.currentPadKeyName) - getKeyNoteIndex('E') + 18) % 12 - 6;
    source.buffer = buffer;
    source.playbackRate.value = 2 ** (semitones / 12);
    source.loop = true;
    source.loopStart = 12;
    source.loopEnd = 47;
    gain.gain.value = 1;
    source.connect(gain);
    gain.connect(state.masterG || c.destination);
    source.onended = () => { source.disconnect(); gain.disconnect(); };
    source.start();
  }).catch(() => {
    if (request === padRequest) startSynthPad();
  });
}

function startSynthPad(k, keyName) {
  const c = getAudioCtx();
  if (c.state === 'suspended') c.resume().catch(() => {});
  stopPad();
  if (k !== undefined) {
    state.currentPadKeyIndex = k;
    state.currentPadKeyName = formatPadNote(keyName || state.RADIO_NOTES[k]?.name || 'C');
  }

  const now = c.currentTime;
  state.padGain = c.createGain();
  state.padGain.gain.setValueAtTime(0.001, now);
  state.padGain.gain.linearRampToValueAtTime(0.09, now + 1.2);

  // Filtro Brillo (Lowpass Cutoff controlado en tiempo real por el fader Brillo)
  state.padFilterNode = c.createBiquadFilter();
  state.padFilterNode.type = 'lowpass';
  state.padFilterNode.frequency.value = 350 + (state.padBrilloVal * 2800);
  state.padFilterNode.Q.value = 1.0;

  const base = state.chromaticFreqs[state.currentPadKeyIndex];
  // 3 osciladores base para el colchón cálido (fundamental, quinta, unísono desafinado)
  const baseFreqs = [base, base * 1.004, base * 1.498];
  state.padOscs = baseFreqs.map(f => {
    const o = c.createOscillator();
    o.type = 'sawtooth';
    o.frequency.value = f;
    o.connect(state.padFilterNode);
    o.start(now);
    return o;
  });

  // Capa Shimmer (octava y doble octava aguda cristalina)
  state.padShimmerGain = c.createGain();
  state.padShimmerGain.gain.value = state.padShimmerVal * 0.045;
  const shimmerFilter = c.createBiquadFilter();
  shimmerFilter.type = 'highpass';
  shimmerFilter.frequency.value = 800;

  const shimmerFreqs = [base * 2.003, base * 4.008];
  state.padShimmerOscs = shimmerFreqs.map(f => {
    const o = c.createOscillator();
    o.type = 'sine';
    o.frequency.value = f;
    o.connect(shimmerFilter);
    o.start(now);
    return o;
  });
  shimmerFilter.connect(state.padShimmerGain);
  state.padShimmerGain.connect(state.padFilterNode);

  // Espacial: Delay estéreo y reverb ambiental
  state.padDelayNode = c.createDelay(1.0);
  state.padDelayNode.delayTime.value = 0.38;
  state.padDelayFB = c.createGain();
  state.padDelayFB.gain.value = 0.45;
  state.padEspacialGain = c.createGain();
  state.padEspacialGain.gain.value = state.padEspacialVal * 0.55;

  state.padFilterNode.connect(state.padGain);
  state.padFilterNode.connect(state.padDelayNode);
  state.padDelayNode.connect(state.padDelayFB);
  state.padDelayFB.connect(state.padDelayNode);
  state.padDelayNode.connect(state.padEspacialGain);
  state.padEspacialGain.connect(state.padGain);

  if (typeof state.masterG !== 'undefined' && state.masterG) {
    state.padGain.connect(state.masterG);
  } else {
    state.padGain.connect(c.destination);
  }

  state.isContinuousPadPlaying = true;
  updatePadRadioUI();
}



export function stopPad() {
  padRequest++;
  const c = state.ctx || (typeof getAudioCtx === 'function' ? getAudioCtx() : null);
  if (state.padGain && c) {
    const now = c.currentTime;
    state.padGain.gain.cancelScheduledValues(now);
    state.padGain.gain.setValueAtTime(state.padGain.gain.value, now);
    const fade = recordedSource ? 1.5 : 0.8;
    state.padGain.gain.linearRampToValueAtTime(0.0001, now + fade);
    if (recordedSource) {
      recordedSource.stop(now + fade);
      recordedSource = null;
    }
    state.padGain = null;
    const oscsToStop = [...state.padOscs, ...state.padShimmerOscs];
    setTimeout(() => {
      oscsToStop.forEach(o => { try { o.stop(); } catch(e){} });
    }, 850);
    state.padOscs = [];
    state.padShimmerOscs = [];
  }
  state.isContinuousPadPlaying = false;
  updatePadRadioUI();
}


/* ---------- Cinta Giratoria (Rotary Tape Ribbon Reel Tuner) ---------- */

export function getTapeCellWidth() {
  const sampleCell = document.querySelector('.pr-tape-cell');
  if (sampleCell) {
    const w = sampleCell.getBoundingClientRect().width || sampleCell.offsetWidth;
    if (w > 0) return w;
  }
  return (window.innerHeight < 550 || (window.innerWidth <= 960 && window.innerWidth > window.innerHeight)) ? 36 : 58;
}



export function scrollPadTapeToNote(noteIdx, animate = true) {
  const viewport = document.getElementById('prTapeViewport');
  const ribbon = document.getElementById('prTapeRibbon');
  if (!viewport || !ribbon) return;

  const cellW = getTapeCellWidth();
  const vpWidth = viewport.clientWidth || 460;
  const vpCenter = vpWidth / 2;
  const targetSlot = (state.TAPE_REF_CYCLE * 12) + noteIdx;
  const targetSlotCenter = (targetSlot * cellW) + (cellW / 2);
  const targetTranslateX = Math.round(vpCenter - targetSlotCenter);

  state.currentTapeTranslateX = targetTranslateX;
  ribbon.style.transition = animate ? 'transform 0.35s cubic-bezier(0.16, 1, 0.3, 1)' : 'none';
  ribbon.style.transform = `translateX(${targetTranslateX}px)`;

  // Resaltar la celda activa bajo la aguja
  ribbon.querySelectorAll('.pr-tape-cell').forEach(cell => {
    const s = +cell.dataset.slot;
    const n = +cell.dataset.noteIdx;
    const isActive = (n === noteIdx && (s === targetSlot || Math.abs(s - targetSlot) % 12 === 0));
    cell.classList.toggle('active', isActive);
  });
}



export function updatePadRadioUI() {
  const baseNote = state.RADIO_NOTES[state.currentPadKeyIndex] || state.RADIO_NOTES[0];
  const note = { ...baseNote, name: state.currentPadKeyName || baseNote.name };
  const curSong = state.SONGS_DATA[state.currentSongIdx] || state.SONGS_DATA[0];
  const nextSong = (state.currentSongIdx < state.SONGS_DATA.length - 1) ? state.SONGS_DATA[state.currentSongIdx + 1] : null;

  // 1. Cabecera
  const led = document.getElementById('prPulseLed');
  const statusBadge = document.getElementById('prStatusBadge');
  if (led) led.classList.toggle('active', state.isContinuousPadPlaying);
  if (statusBadge) {
    statusBadge.textContent = state.isContinuousPadPlaying ? 'activo' : 'en espera';
    statusBadge.classList.toggle('active', state.isContinuousPadPlaying);
  }

  // 2. Pantalla Inset (Cuadro de Tonalidad)
  const bigKey = document.getElementById('prBigKey');
  const keyMode = document.getElementById('prKeyMode');

  if (bigKey) {
    bigKey.textContent = note.name;
    bigKey.classList.toggle('active', state.isContinuousPadPlaying);
  }
  if (keyMode) {
    keyMode.textContent = 'MAYOR';
    keyMode.classList.toggle('active', state.isContinuousPadPlaying);
  }

  // 3. Cinta Giratoria (Girar suavemente hacia la nota activa)
  scrollPadTapeToNote(state.currentPadKeyIndex, true);

  // 4. Puente a la siguiente & Botón de Encendido
  const bridgeVal = document.getElementById('prBridgeVal');
  if (bridgeVal) {
    bridgeVal.textContent = nextSong ? `${curSong.key} → ${nextSong.key} · 4 compases` : 'FINAL DEL SETLIST';
  }

  const pwrBtn = document.getElementById('prPowerBtn');
  if (pwrBtn) {
    pwrBtn.textContent = state.isContinuousPadPlaying ? 'APAGAR PAD' : 'ENCENDER PAD';
    pwrBtn.classList.toggle('active', state.isContinuousPadPlaying);
  }

  const padKey = document.getElementById('moPadKey');
  const padButton = document.getElementById('moPadBtn');
  if (padKey) padKey.textContent = note.name;
  if (padButton) padButton.classList.toggle('on', state.isContinuousPadPlaying);
  updateMoPadPicker();
}



export function updateMoPadPicker() {
  const grid = document.getElementById('moPadNoteGrid');
  if (grid && grid.dataset.ready !== 'true') {
    grid.innerHTML = state.PAD_NOTE_OPTIONS.map(note =>
      `<button type="button" class="mo-pad-note-option" data-note="${note}" aria-pressed="false" onclick="selectMoPadNote('${note}')">${note}</button>`
    ).join('');
    grid.dataset.ready = 'true';
  }

  const picker = document.getElementById('moPadPicker');
  if (!picker) return;
  picker.classList.toggle('theme-light', document.documentElement.getAttribute('data-theme') === 'light');
  const selectedNote = state.currentPadKeyName || 'E';
  picker.querySelectorAll('.mo-pad-note-option').forEach(button => {
    const selected = button.dataset.note === selectedNote;
    button.classList.toggle('active', selected);
    button.setAttribute('aria-pressed', String(selected));
  });
  const followToggle = document.getElementById('moPadFollowToggle');
  if (followToggle) followToggle.checked = state.padFollowSetlist;
  const songKey = document.getElementById('moPadPickerSongKey');
  if (songKey) songKey.textContent = state.SONG ? `Canción: ${formatMusicalKey(state.SONG.key)}` : 'Sin canción activa';
  const powerButton = document.getElementById('moPadPowerToggle');
  if (powerButton) powerButton.textContent = state.isContinuousPadPlaying ? 'APAGAR PAD' : 'ENCENDER PAD';
}



export function openMoPadPicker() {
  updateMoPadPicker();
  const picker = document.getElementById('moPadPicker');
  const trigger = document.getElementById('moPadBtn');
  if (picker) {
    picker.classList.add('open');
    picker.setAttribute('aria-hidden', 'false');
  }
  if (trigger) trigger.setAttribute('aria-expanded', 'true');
}



export function closeMoPadPicker() {
  const picker = document.getElementById('moPadPicker');
  const trigger = document.getElementById('moPadBtn');
  if (picker) {
    picker.classList.remove('open');
    picker.setAttribute('aria-hidden', 'true');
  }
  if (trigger) trigger.setAttribute('aria-expanded', 'false');
}



export function selectMoPadNote(key) {
  state.currentPadKeyName = formatPadNote(key);
  state.currentPadKeyIndex = getKeyNoteIndex(state.currentPadKeyName);
  state.padFollowSetlist = false;
  const legacyFollow = document.getElementById('prFollowSetlist');
  if (legacyFollow) legacyFollow.checked = false;
  if (state.isContinuousPadPlaying) startPad(state.currentPadKeyIndex, state.currentPadKeyName);
  else updatePadRadioUI();
  say(`PAD: TONO MANUAL ${state.currentPadKeyName}`);
  closeMoPadPicker();
}



export function setMoPadFollowSetlist(enabled) {
  state.padFollowSetlist = Boolean(enabled);
  const legacyFollow = document.getElementById('prFollowSetlist');
  if (legacyFollow) legacyFollow.checked = state.padFollowSetlist;
  if (state.padFollowSetlist && state.SONG) {
    state.currentPadKeyName = formatPadNote(state.SONG.key);
    state.currentPadKeyIndex = getKeyNoteIndex(state.currentPadKeyName);
    if (state.isContinuousPadPlaying) startPad(state.currentPadKeyIndex, state.currentPadKeyName);
    else updatePadRadioUI();
  } else {
    updateMoPadPicker();
  }
}



export function setupHorizontalFader(trackId, barId, thumbId, initialVal, onUpdate) {
  const track = document.getElementById(trackId);
  const bar = document.getElementById(barId);
  const thumb = document.getElementById(thumbId);
  if (!track || !bar || !thumb) return;

  const updateUI = (val) => {
    const pct = (val * 100).toFixed(1) + '%';
    bar.style.width = pct;
    thumb.style.left = pct;
  };

  updateUI(initialVal);

  let isDragging = false;

  const handleDrag = (clientX) => {
    const rect = track.getBoundingClientRect();
    const inset = 10;
    const width = Math.max(1, rect.width - (inset * 2));
    const clickX = state.clamp(clientX - rect.left - inset, 0, width);
    const ratio = state.clamp(clickX / width, 0, 1);
    updateUI(ratio);
    if (onUpdate) onUpdate(ratio);
  };

  track.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    isDragging = true;
    try { track.setPointerCapture(e.pointerId); } catch (_) {}
    handleDrag(e.clientX);
  });

  track.addEventListener('pointermove', (e) => {
    if (isDragging) {
      e.preventDefault();
      handleDrag(e.clientX);
    }
  });

  const stopFaderDrag = (e) => {
    if (isDragging) {
      isDragging = false;
      try { track.releasePointerCapture(e.pointerId); } catch (_) {}
    }
  };

  track.addEventListener('pointerup', stopFaderDrag);
  track.addEventListener('pointercancel', stopFaderDrag);

  // Soporte de rueda del ratón
  track.addEventListener('wheel', (e) => {
    e.preventDefault();
    const curWidth = parseFloat(bar.style.width) / 100 || 0;
    const step = (e.deltaY || e.deltaX) < 0 ? 0.05 : -0.05;
    const nextVal = state.clamp(curWidth + step, 0, 1);
    updateUI(nextVal);
    if (onUpdate) onUpdate(nextVal);
  }, { passive: false });
}



export function bindPadRadio() {
  // Renderizar e inicializar la Cinta Giratoria de Selección de Notas
  const tapeRibbon = document.getElementById('prTapeRibbon');
  const tapeViewport = document.getElementById('prTapeViewport');
  const tapeChassis = document.getElementById('prTapeChassis');

  if (tapeRibbon && tapeViewport && tapeChassis) {
    let cellsHtml = '';
    let slotCount = 0;
    for (let c = 0; c < state.TAPE_TOTAL_CYCLES; c++) {
      for (let i = 0; i < state.RADIO_NOTES.length; i++) {
        const n = state.RADIO_NOTES[i];
        const isSelected = (c === state.TAPE_REF_CYCLE && i === state.currentPadKeyIndex);
        cellsHtml += `
          <div class="pr-tape-cell ${isSelected ? 'active' : ''}" data-slot="${slotCount}" data-note-idx="${i}" title="Sintonizar Pad en ${n.name} (${n.tone})">
            <div class="pr-tape-ticks">
              <span class="pr-tick-major"></span>
              <span class="pr-tick-sub s1"></span>
              <span class="pr-tick-sub s2"></span>
              <span class="pr-tick-sub s3"></span>
            </div>
            <div class="pr-tape-note">${n.name}</div>
            <div class="pr-tape-sub">${n.tone.split(' ')[0]}</div>
          </div>
        `;
        slotCount++;
      }
    }
    tapeRibbon.innerHTML = cellsHtml;

    // Centrar inicialmente
    scrollPadTapeToNote(state.currentPadKeyIndex, false);
    requestAnimationFrame(() => scrollPadTapeToNote(state.currentPadKeyIndex, false));
    setTimeout(() => scrollPadTapeToNote(state.currentPadKeyIndex, false), 120);

    // Clic en cualquier nota de la cinta
    tapeRibbon.querySelectorAll('.pr-tape-cell').forEach(cell => {
      cell.addEventListener('click', (e) => {
        e.stopPropagation();
        const noteIdx = +cell.dataset.noteIdx;
        if (state.isContinuousPadPlaying && state.currentPadKeyIndex === noteIdx) {
          stopPad();
          say('PAD CONTINUO: DESACTIVADO');
        } else {
          startPad(noteIdx);
          say(`PAD SINTONIZADO EN ${state.RADIO_NOTES[noteIdx].name}`);
        }
      });
    });

    // Soporte para arrastre (drag/swipe) de la cinta giratoria
    const onTapeDragStart = (clientX) => {
      state.isTapeDragging = true;
      state.tapeDragStartX = clientX;
      state.tapeDragStartTranslateX = state.currentTapeTranslateX;
      tapeRibbon.style.transition = 'none';
      tapeChassis.classList.add('dragging');
    };

    const onTapeDragMove = (clientX) => {
      if (!state.isTapeDragging) return;
      const deltaX = clientX - state.tapeDragStartX;
      state.currentTapeTranslateX = state.tapeDragStartTranslateX + deltaX;
      tapeRibbon.style.transform = `translateX(${state.currentTapeTranslateX}px)`;

      // Feedback visual en vivo durante el arrastre
      const cellW = getTapeCellWidth();
      const vpWidth = tapeViewport.clientWidth || 460;
      const vpCenter = vpWidth / 2;
      const slotCenterOffset = vpCenter - state.currentTapeTranslateX;
      const nearestSlot = state.clamp(Math.round((slotCenterOffset - cellW / 2) / cellW), 0, (state.TAPE_TOTAL_CYCLES * 12) - 1);
      tapeRibbon.querySelectorAll('.pr-tape-cell').forEach(cell => {
        const s = +cell.dataset.slot;
        cell.classList.toggle('active', s === nearestSlot);
      });
    };

    const onTapeDragEnd = () => {
      if (!state.isTapeDragging) return;
      state.isTapeDragging = false;
      tapeChassis.classList.remove('dragging');

      const cellW = getTapeCellWidth();
      const vpWidth = tapeViewport.clientWidth || 460;
      const vpCenter = vpWidth / 2;
      const slotCenterOffset = vpCenter - state.currentTapeTranslateX;
      const nearestSlot = state.clamp(Math.round((slotCenterOffset - cellW / 2) / cellW), 0, (state.TAPE_TOTAL_CYCLES * 12) - 1);
      const noteIdx = ((nearestSlot % 12) + 12) % 12;

      if (noteIdx !== state.currentPadKeyIndex) {
        if (state.isContinuousPadPlaying) {
          startPad(noteIdx);
        } else {
          state.currentPadKeyIndex = noteIdx;
          state.currentPadKeyName = state.RADIO_NOTES[noteIdx].name;
          updatePadRadioUI();
        }
      } else {
        scrollPadTapeToNote(state.currentPadKeyIndex, true);
      }
    };

    tapeChassis.addEventListener('mousedown', (e) => {
      onTapeDragStart(e.clientX);
    });
    window.addEventListener('mousemove', (e) => {
      if (state.isTapeDragging) onTapeDragMove(e.clientX);
    });
    window.addEventListener('mouseup', () => {
      if (state.isTapeDragging) onTapeDragEnd();
    });

    // Soporte táctil en la cinta
    tapeChassis.addEventListener('touchstart', (e) => {
      if (e.touches && e.touches[0]) onTapeDragStart(e.touches[0].clientX);
    }, { passive: true });
    window.addEventListener('touchmove', (e) => {
      if (state.isTapeDragging && e.touches && e.touches[0]) onTapeDragMove(e.touches[0].clientX);
    }, { passive: true });
    window.addEventListener('touchend', () => {
      if (state.isTapeDragging) onTapeDragEnd();
    });

    // Rueda del ratón sobre el chasis de la cinta para sintonizar
    tapeChassis.addEventListener('wheel', (e) => {
      e.preventDefault();
      const dir = (e.deltaY || e.deltaX) > 0 ? 1 : -1;
      const nextIdx = (state.currentPadKeyIndex + dir + 12) % 12;
      if (state.isContinuousPadPlaying) {
        startPad(nextIdx);
      } else {
        state.currentPadKeyIndex = nextIdx;
        state.currentPadKeyName = state.RADIO_NOTES[nextIdx].name;
        updatePadRadioUI();
      }
    }, { passive: false });
  }

  // Botones de paso ‹ y › (nudge semitono)
  const prevBtn = document.getElementById('prTapePrevBtn');
  if (prevBtn) {
    prevBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const prevIdx = (state.currentPadKeyIndex - 1 + 12) % 12;
      if (state.isContinuousPadPlaying) startPad(prevIdx);
      else {
        state.currentPadKeyIndex = prevIdx;
        state.currentPadKeyName = state.RADIO_NOTES[prevIdx].name;
        updatePadRadioUI();
      }
    });
  }
  const nextBtn = document.getElementById('prTapeNextBtn');
  if (nextBtn) {
    nextBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const nextIdx = (state.currentPadKeyIndex + 1) % 12;
      if (state.isContinuousPadPlaying) startPad(nextIdx);
      else {
        state.currentPadKeyIndex = nextIdx;
        state.currentPadKeyName = state.RADIO_NOTES[nextIdx].name;
        updatePadRadioUI();
      }
    });
  }

  // Recalcular posición al redimensionar ventana
  window.addEventListener('resize', () => {
    scrollPadTapeToNote(state.currentPadKeyIndex, false);
  });

  // Toggle "sigue al setlist"
  const followToggle = document.getElementById('prFollowSetlist');
  if (followToggle) {
    followToggle.checked = state.padFollowSetlist;
    followToggle.addEventListener('change', () => {
      setMoPadFollowSetlist(followToggle.checked);
      say(state.padFollowSetlist ? 'PAD: SIGUE AL SETLIST ACTIVADO' : 'PAD: TONO MANUAL FIJO');
    });
  }

  // Botón Encender / Apagar Pad
  const pwrBtn = document.getElementById('prPowerBtn');
  if (pwrBtn) {
    pwrBtn.addEventListener('click', () => {
      if (state.isContinuousPadPlaying) {
        stopPad();
        say('PAD CONTINUO: APAGADO');
      } else {
        startPad(state.currentPadKeyIndex, state.currentPadKeyName);
        say(`PAD CONTINUO: ENCENDIDO EN ${state.currentPadKeyName}`);
      }
    });
  }

  // Configuración de los 3 Faders Horizontales (Shimmer, Espacial, Brillo)
  setupHorizontalFader('faderTrackShimmer', 'faderBarShimmer', 'faderThumbShimmer', state.padShimmerVal, (val) => {
    state.padShimmerVal = val;
    if (state.padShimmerGain && state.ctx) {
      state.padShimmerGain.gain.setValueAtTime(val * 0.045, state.ctx.currentTime);
    }
  });

  setupHorizontalFader('faderTrackEspacial', 'faderBarEspacial', 'faderThumbEspacial', state.padEspacialVal, (val) => {
    state.padEspacialVal = val;
    if (state.padEspacialGain && state.ctx) {
      state.padEspacialGain.gain.setValueAtTime(val * 0.55, state.ctx.currentTime);
    }
  });

  setupHorizontalFader('faderTrackBrillo', 'faderBarBrillo', 'faderThumbBrillo', state.padBrilloVal, (val) => {
    state.padBrilloVal = val;
    if (state.padFilterNode && state.ctx) {
      state.padFilterNode.frequency.setValueAtTime(350 + (val * 2800), state.ctx.currentTime);
    }
  });

  updatePadRadioUI();
}

export function initializePads() {
  document.getElementById('moPadVoice')?.addEventListener('change', () => {
    if (state.isContinuousPadPlaying) startPad();
  });


/* ---------- Sintetizador de Pad Continuo Tipo Radio Vintage ---------- */
state.padGain = null;

state.padFilterNode = null;

state.padOscs = [];

state.padShimmerOscs = [];

state.padShimmerGain = null;

state.padDelayNode = null;

state.padDelayFB = null;

state.padEspacialGain = null;


state.chromaticFreqs = [130.81, 138.59, 146.83, 155.56, 164.81, 174.61, 185.00, 196.00, 207.65, 220.00, 233.08, 246.94];

state.currentPadKeyIndex = 4;
 // 'E' por defecto
state.currentPadKeyName = 'E';

state.isContinuousPadPlaying = false;

state.padFollowSetlist = true;

state.padShimmerVal = 0.50;

state.padEspacialVal = 0.65;

state.padBrilloVal = 0.55;


state.RADIO_NOTES = [
  { name: 'C',  freqIdx: 0, tone: 'Do' },
  { name: 'C#', freqIdx: 1, tone: 'Do sostenido' },
  { name: 'D',  freqIdx: 2, tone: 'Re' },
  { name: 'D#', freqIdx: 3, tone: 'Re sostenido' },
  { name: 'E',  freqIdx: 4, tone: 'Mi' },
  { name: 'F',  freqIdx: 5, tone: 'Fa' },
  { name: 'F#', freqIdx: 6, tone: 'Fa sostenido' },
  { name: 'G',  freqIdx: 7, tone: 'Sol' },
  { name: 'G#', freqIdx: 8, tone: 'Sol sostenido' },
  { name: 'A',  freqIdx: 9, tone: 'La' },
  { name: 'A#', freqIdx: 10, tone: 'La sostenido' },
  { name: 'B',  freqIdx: 11, tone: 'Si' }
];

state.PAD_CHORDS = state.RADIO_NOTES;
 // Alias de compatibilidad
state.PAD_NOTE_OPTIONS = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

state.TAPE_CELL_WIDTH = 58;
 // Fallback estático
state.TAPE_TOTAL_CYCLES = 5;

state.TAPE_REF_CYCLE = 2;
 // Ciclo central de referencia (slots 24..35)
state.currentTapeTranslateX = 0;

state.isTapeDragging = false;

state.tapeDragStartX = 0;

state.tapeDragStartTranslateX = 0;

state.updatePadWheelUI = updatePadRadioUI;


document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') closeMoPadPicker();
});

state.bindPadWheel = bindPadRadio;
}

