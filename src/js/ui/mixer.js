import { gainToDb, dbToGain, gainToPosition, positionToGain } from '../audio/levels.js';
import { drawWave } from './timeline.js';
import { state } from '../state/store.js';
import { orderMixerStemKeys, isMixerPriorityCue } from '../audio/engine.js';
import { applyMix, setMasterLevel, syncChannels } from '../audio/transport.js';
import { say } from './show.js';
import { openEq } from './eq.js';
import { restoreEq } from '../audio/eq.js';

let mixerSong;
const restoredChannels = new Set();


export function renderMixer() {
  const mixerEl = state.$('#mixer');
  if (!mixerEl) return;
  if (mixerSong !== state.SONG) {
    mixerSong = state.SONG;
    restoredChannels.clear();
  }
  for (const id of [...state.stemKeys, 'master']) {
    const channel = state.STEMS[id];
    if (!channel || restoredChannels.has(id)) continue;
    restoredChannels.add(id);
    const gain = state.SONG?.mix?.[id]?.gain;
    channel.gain = Number.isFinite(gain) ? dbToGain(gainToDb(gain)) : (channel.def ?? 1);
    channel.muted = state.SONG?.mix?.[id]?.muted === true;
    channel.solo = state.SONG?.mix?.[id]?.solo === true;
  }
  restoreEq('master');
  state.stemKeys = orderMixerStemKeys(state.stemKeys);
  let h = '';

  // Canales de pistas individuales
  for (const s of state.stemKeys) {
    const st = state.STEMS[s];
    if (!st) continue;
    const isPriorityCue = isMixerPriorityCue(s);
    if (!isPriorityCue) restoreEq(s);
    h += `<div class="ch${isPriorityCue ? ' ch-priority-cue' : ''}" data-stem="${s}">
      <span class="ch-name" title="${st.label}">${st.label}</span>
      ${isPriorityCue ? '' : `<button type="button" class="chbtn" data-stem="${s}" data-act="eq" aria-haspopup="dialog">EQ</button>`}
      <div class="ch-strip">
        <canvas class="ch-meter" data-stem="${s}" role="img" aria-label="Medidor ${st.label}"></canvas>
        <div class="fader" data-stem="${s}" role="slider" aria-label="Nivel ${st.label}" tabindex="0" aria-valuemin="-60" aria-valuemax="10">
          <span class="fader-unity" aria-hidden="true">0</span><span class="fader-limit fader-limit-high" aria-hidden="true">+10</span><span class="fader-limit fader-limit-low" aria-hidden="true">−60</span><div class="fader-cap"></div>
        </div>
      </div>
      <div class="ch-btns">
        <button type="button" class="chbtn bm${st.muted ? ' on' : ''}" data-stem="${s}" data-act="m" aria-label="Silenciar ${st.label}">M</button>
        ${s === 'click' || s === 'talkback' ? '<span style="width:24px"></span>' : `<button type="button" class="chbtn bs${st.solo ? ' on' : ''}" data-stem="${s}" data-act="s" aria-label="Solo ${st.label}">S</button>`}
      </div>
      <span class="ch-db" data-stem="${s}">${state.fmtDb(st.gain)}</span>
    </div>`;
  }

  // Canal Master sticky a la derecha
  const mst = state.STEMS.master;
  h += `<div class="master-backdrop">
    <div class="ch master" data-stem="master">
      <span class="ch-name">${mst.label}</span>
      <button type="button" class="chbtn" data-stem="master" data-act="eq" aria-haspopup="dialog">EQ</button>
      <div class="ch-strip">
        <canvas class="ch-meter" data-stem="master" role="img" aria-label="Medidor Master"></canvas>
        <div class="fader" data-stem="master" role="slider" aria-label="Nivel Master" tabindex="0" aria-valuemin="-60" aria-valuemax="10">
          <span class="fader-unity" aria-hidden="true">0</span><span class="fader-limit fader-limit-high" aria-hidden="true">+10</span><span class="fader-limit fader-limit-low" aria-hidden="true">−60</span><div class="fader-cap"></div>
        </div>
      </div>
      <div class="ch-btns">
        <button type="button" class="chbtn bm${mst.muted ? ' on' : ''}" data-stem="master" data-act="m" aria-label="Silenciar Master">M</button>
        <span style="width:24px"></span>
      </div>
      <span class="ch-db" data-stem="master">${state.fmtDb(mst.gain)}</span>
    </div>
  </div>`;

  mixerEl.innerHTML = h;

  state.meterCv = {};
  mixerEl.querySelectorAll('.ch-meter').forEach(c => state.meterCv[c.dataset.stem] = c);

  // Faders con arrastre continuo
  mixerEl.querySelectorAll('.fader').forEach(f => {
    const s = f.dataset.stem;
    const dbEl = mixerEl.querySelector(`.ch-db[data-stem="${s}"]`);
    const setUI = v => { f.style.setProperty('--v', gainToPosition(v)); f.setAttribute('aria-valuenow', gainToDb(v).toFixed(1)); f.setAttribute('aria-valuetext', state.fmtDb(v)); if (dbEl) dbEl.textContent = state.fmtDb(v); };
    setUI(state.STEMS[s].gain);
    const setV = v => {
      if (s === 'master') return setMasterLevel(gainToDb(v));
      v = dbToGain(gainToDb(v));
      state.STEMS[s].gain = v;
      setUI(v);
      applyMix();
      syncChannels();
      drawWave(s);
    };
    f.addEventListener('pointerdown', e => {
      e.preventDefault(); f.focus();
      const r = f.getBoundingClientRect();
      const capHeight = f.querySelector('.fader-cap').offsetHeight;
      const go = ev => setV(positionToGain((r.bottom - capHeight / 2 - ev.clientY) / Math.max(1, r.height - capHeight)));
      go(e);
      const mv = ev => go(ev), up = () => { removeEventListener('pointermove', mv); removeEventListener('pointerup', up); };
      addEventListener('pointermove', mv); addEventListener('pointerup', up);
    });
    f.addEventListener('dblclick', () => setV(1));
    f.addEventListener('wheel', e => { e.preventDefault(); e.stopPropagation(); setV(dbToGain(gainToDb(state.STEMS[s].gain) + (e.deltaY < 0 ? 1 : -1))); }, { passive: false });
    f.addEventListener('keydown', e => {
      if (e.key === 'Home' || e.key === 'End') { e.preventDefault(); setV(dbToGain(e.key === 'Home' ? -60 : 10)); }
      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') { e.preventDefault(); setV(dbToGain(gainToDb(state.STEMS[s].gain) + (e.key === 'ArrowUp' ? 1 : -1))); }
    });
  });

  if (!mixerEl.dataset.eventsBound) {
    mixerEl.addEventListener('click', e => {
      const b = e.target.closest('.chbtn'); if (!b) return;
      const s = b.dataset.stem, st = state.STEMS[s];
      if (!st) return;
      if (b.dataset.act === 'eq') { openEq(s, st.label); return; }
      if (b.dataset.act === 'm') st.muted = !st.muted; else st.solo = !st.solo;
      b.classList.toggle('on', b.dataset.act === 'm' ? st.muted : st.solo);
      applyMix();
      syncChannels(); // Sincroniza Stage Header Master Mute si se requiere
      say((b.dataset.act === 'm' ? 'MUTE' : 'SOLO') + ' — ' + st.label + (b.classList.contains('on') ? ' ON' : ' OFF'));
      if (s === 'click') {
        const ct = state.$('#clickTgl');
        if (ct) ct.classList.toggle('on', !st.muted);
      }
    });

    // Desplazamiento horizontal fluido con la rueda del ratón en la consola de faders
    mixerEl.addEventListener('wheel', e => {
      if (!e.target.closest('.fader')) {
        e.preventDefault();
        mixerEl.scrollLeft += (e.deltaY || e.deltaX) * 1.5;
      }
    }, { passive: false });
    
    mixerEl.dataset.eventsBound = "true";
  }
}


/* Helpers para gestión dinámica de pistas (hasta 20 stems) */

export function updateStemCountBadge() {
  const badge = document.getElementById('stemCountBadge');
  const meta = state.$('#cSongMeta');
  const title = state.$('#cSongTitle');
  if (!state.SONG) {
    if (badge) badge.textContent = `0 STEMS`;
    if (meta) meta.textContent = `VACÍO`;
    if (title) title.textContent = `SELECCIONA UNA CANCIÓN`;
    return;
  }
  if (badge) badge.textContent = `${state.stemKeys.length} STEMS`;
  if (title) title.textContent = state.SONG.title;
  if (meta) {
    meta.textContent = state.SONG.artist || '';
  }
}

export function initializeMixer() {


/* ==========================================================================
   RENDER DE CONSOLA (MIXER INFERIOR + TIMELINE SUPERIOR)
   ========================================================================== */
state.meterCv = {};
}

