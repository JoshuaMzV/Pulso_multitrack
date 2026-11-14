import { state } from '../state/store.js';
import { getKeyNoteIndex, getSongRootKey, formatPadNote, formatMusicalKey } from './pads.js';
import { destroyRealStretchRoutes, setTransposeCompensationDelay, restartRealStemsAt } from './stems.js';
import { syncModernUI, say } from '../ui/show.js';
import { getBeat16, jumpTo } from './transport.js';



export function getTransposeOffsetForKey(targetKey) {
  if (!state.SONG) return 0;
  const originalIndex = getKeyNoteIndex(getSongRootKey(state.SONG.key));
  const targetIndex = getKeyNoteIndex(formatPadNote(targetKey));
  let offset = (targetIndex - originalIndex + 12) % 12;
  if (offset > 6) offset -= 12;
  return offset;
}



export function resetTransposeForCurrentSong() {
  state.transposeTargetKey = state.SONG?.transposeKey ? formatPadNote(state.SONG.transposeKey) : null;
  state.transposeSemitones = state.transposeTargetKey ? getTransposeOffsetForKey(state.transposeTargetKey) : 0;
  destroyRealStretchRoutes();
  setTransposeCompensationDelay(0);
}



export function updateTransposePicker() {
  const grid = document.getElementById('moTransposeNoteGrid');
  if (grid && grid.dataset.ready !== 'true') {
    grid.innerHTML = state.PAD_NOTE_OPTIONS.map(note =>
      `<button type="button" class="mo-pad-note-option" data-note="${note}" aria-pressed="false" onclick="selectTransposeKey('${note}')"><span>${note}</span></button>`
    ).join('');
    grid.dataset.ready = 'true';
  }
  const picker = document.getElementById('moTransposePicker');
  if (!picker) return;
  const originalKey = state.SONG ? getSongRootKey(state.SONG.key) : 'C';
  const currentKey = state.transposeTargetKey || originalKey;
  const summary = document.getElementById('moTransposeSummary');
  if (summary) summary.textContent = `Sonando: ${currentKey}`;
  grid?.querySelectorAll('.mo-pad-note-option').forEach(button => {
    const selected = button.dataset.note === currentKey;
    const original = button.dataset.note === originalKey;
    button.classList.toggle('active', selected);
    button.classList.toggle('original', original);
    button.setAttribute('aria-pressed', String(selected));
    let originalLabel = button.querySelector('.mo-original-label');
    if (original && !originalLabel) {
      originalLabel = document.createElement('small');
      originalLabel.className = 'mo-original-label';
      originalLabel.textContent = 'ORIGINAL';
      button.appendChild(originalLabel);
    } else if (!original && originalLabel) {
      originalLabel.remove();
    }
  });
}



export function syncTransposeKeyBadges() {
  if (!state.SONG) return;
  const originalKey = formatMusicalKey(state.SONG.key || 'C');
  const currentKey = state.transposeTargetKey || getSongRootKey(state.SONG.key || 'C');
  const editBadge = document.getElementById('heroKeyBadge');
  if (editBadge) {
    const currentLabel = editBadge.querySelector('#heroKeyCurrent');
    if (currentLabel) currentLabel.textContent = currentKey;
    else editBadge.textContent = currentKey;
    editBadge.classList.toggle('transposed', state.transposeSemitones !== 0);
    editBadge.title = state.transposeSemitones === 0
      ? `Tonalidad original: ${originalKey}. Pulsa para transponer.`
      : `Original: ${originalKey} · Sonando: ${currentKey}. Pulsa para cambiar.`;
    editBadge.setAttribute('aria-label', `Tonalidad actual ${currentKey}. Original ${originalKey}. Cambiar transposición`);
  }

  document.querySelectorAll('.sc-key-pill').forEach(pill => {
    const song = state.SONGS_DATA[Number(pill.dataset.songIndex)];
    if (!song) return;
    const songOriginal = formatMusicalKey(song.key || 'C');
    const songCurrent = song.transposeKey || getSongRootKey(song.key || 'C');
    const currentLabel = pill.querySelector('.sc-key-current');
    if (currentLabel) currentLabel.textContent = songCurrent;
    else pill.textContent = songCurrent;
    pill.classList.toggle('transposed', !!song.transposeKey);
    pill.title = song.transposeKey
      ? `Original: ${songOriginal} · Sonando: ${songCurrent}. Pulsa para cambiar.`
      : `Tonalidad original: ${songOriginal}. Pulsa para transponer.`;
    pill.setAttribute('aria-label', `Tonalidad actual ${songCurrent}. Original ${songOriginal}. Cambiar transposición`);
  });
}



export function openTransposePicker() {
  if (!state.SONG) return;
  updateTransposePicker();
  const picker = document.getElementById('moTransposePicker');
  if (picker) {
    if (picker.parentElement !== document.body) document.body.appendChild(picker);
    picker.classList.add('open');
    picker.setAttribute('aria-hidden', 'false');
  }
  document.querySelectorAll('#moHeroKey, #heroKeyBadge, .sc-key-pill').forEach(button => button.setAttribute('aria-expanded', 'true'));
}



export function closeTransposePicker() {
  const picker = document.getElementById('moTransposePicker');
  if (picker) {
    picker.classList.remove('open');
    picker.setAttribute('aria-hidden', 'true');
  }
  document.querySelectorAll('#moHeroKey, #heroKeyBadge, .sc-key-pill').forEach(button => button.setAttribute('aria-expanded', 'false'));
}



export async function selectTransposeKey(key) {
  if (!state.SONG) return;
  const songForChange = state.SONG;
  const previousOffset = state.transposeSemitones;
  const previousTarget = state.transposeTargetKey;
  const originalKey = getSongRootKey(state.SONG.key);
  const selectedKey = formatPadNote(key);
  state.transposeTargetKey = selectedKey === originalKey ? null : selectedKey;
  state.transposeSemitones = state.transposeTargetKey ? getTransposeOffsetForKey(state.transposeTargetKey) : 0;
  state.SONG.transposeKey = state.transposeTargetKey;
  updateTransposePicker();
  syncTransposeKeyBadges();
  syncModernUI(typeof state.current16th === 'number' ? state.current16th : 0);
  closeTransposePicker();
  say(state.transposeSemitones === 0
    ? `TRANSPOSICIÓN: TONO ORIGINAL ${originalKey}`
    : `TRANSPOSICIÓN: ${originalKey} → ${selectedKey} (${state.transposeSemitones > 0 ? '+' : ''}${state.transposeSemitones})`);

  if (state.isPlaying && previousOffset !== state.transposeSemitones && Object.keys(state.REAL_STEM_BUFFERS).length) {
    const beat16 = Math.max(0, getBeat16());
    const applied = await restartRealStemsAt(beat16 * state.stepSec());
    if (!applied && state.SONG === songForChange) {
      state.transposeTargetKey = previousTarget;
      state.transposeSemitones = previousOffset;
      state.SONG.transposeKey = previousTarget;
      updateTransposePicker();
      syncTransposeKeyBadges();
      syncModernUI(typeof state.current16th === 'number' ? state.current16th : 0);
    }
  } else if (state.isPlaying && previousOffset !== state.transposeSemitones) {
    jumpTo(Math.max(0, Math.floor(getBeat16())));
  }
}
