import { formatGain } from '../audio/levels.js';
import { state } from './store.js';


export function initializeState() {




/* ==========================================================================
   PULSO MULTITRACK ENGINE & CONSOLE CONTROLLER
   ========================================================================== */
state.$ = s => document.querySelector(s);

state.$$ = s => [...document.querySelectorAll(s)];

state.clamp = (v, min, max) => Math.min(max, Math.max(min, v));

state.fract = x => x - Math.floor(x);

state.jr = n => state.fract(Math.sin(n * 127.1 + 311.7) * 43758.5453);

state.fmtDb = formatGain;

state.fmtTime = s => {
  const m = Math.floor(s / 60), r = s - m * 60;
  return String(m).padStart(2, '0') + ':' + (r < 10 ? '0' : '') + r.toFixed(1);
};


/* ---------- Catálogo Maestro de Canciones Disponibles ---------- */
state.DEFAULT_SONGS_CATALOG = [];


/* ---------- Colección de Setlists Disponibles ---------- */
state.ALL_SETLISTS = [
  {
    id: 'setlist-domingo',
    name: 'SETLIST DOMINGO',
    description: 'Servicio Principal',
    songs: []
  }
];


state.currentSetlistIdx = 0;

state.SONGS_DATA = state.ALL_SETLISTS[state.currentSetlistIdx].songs;

state.currentSongIdx = 0;

state.SONG = state.SONGS_DATA[0] || null;

state.bpm = state.SONG ? state.SONG.bpm : 120;


/* ---------- Catálogo Completo de Stems (Hasta 20 Stems Profesionales) ---------- */
state.ALL_STEMS_CATALOG = [
  { id: 'click',      label: 'CLICK METR',   gain: .55, def: .55, type: 'click' },
  { id: 'talkback',   label: 'TALKBACK CUE', gain: .55, def: .55, type: 'click' },
  { id: 'lead',       label: 'GUÍA DIR',     gain: .55, def: .55, type: 'lead' },
  { id: 'drums',      label: 'BATERÍA KICK', gain: .85, def: .85, type: 'drums' },
  { id: 'drums_oh',   label: 'PLATOS / OH',  gain: .75, def: .75, type: 'drums' },
  { id: 'perc',       label: 'PERCUSIÓN',    gain: .70, def: .70, type: 'drums' },
  { id: 'loop_fx',    label: 'LOOP FX',      gain: .65, def: .65, type: 'drums' },
  { id: 'bass',       label: 'BAJO 5 STR',   gain: .80, def: .80, type: 'bass' },
  { id: 'sub_bass',   label: 'SUB 808',      gain: .72, def: .72, type: 'bass' },
  { id: 'guit_ac',    label: 'GUIT. ACÚS L', gain: .65, def: .65, type: 'guitar' },
  { id: 'guit_ac2',   label: 'GUIT. ACÚS R', gain: .65, def: .65, type: 'guitar' },
  { id: 'guit_el1',   label: 'GUIT. LEAD',   gain: .70, def: .70, type: 'guitar' },
  { id: 'guit_el2',   label: 'GUIT. RITMO',  gain: .68, def: .68, type: 'guitar' },
  { id: 'keys',       label: 'PIANO COLA',   gain: .60, def: .60, type: 'keys' },
  { id: 'organ',      label: 'ORGANO B3',    gain: .50, def: .50, type: 'keys' },
  { id: 'pad_amb',    label: 'PAD WIDE',     gain: .58, def: .58, type: 'pad' },
  { id: 'strings',    label: 'CUERDAS',      gain: .55, def: .55, type: 'pad' },
  { id: 'brass',      label: 'METALES',      gain: .60, def: .60, type: 'lead' },
  { id: 'bgv_choir',  label: 'COROS ALTO',   gain: .58, def: .58, type: 'pad' },
  { id: 'vox_lead',   label: 'VOZ PRINCIPAL',gain: .75, def: .75, type: 'lead' }
];


state.STEMS = {
  master: { label: 'MASTER', gain: .90, def: .90, muted: false, solo: false }
};


state.ALL_STEMS_CATALOG.forEach(s => {
  state.STEMS[s.id] = {
    label: s.label,
    gain: s.gain,
    def: s.def,
    type: s.type,
    muted: false,
    solo: false,
    node: null,
    ana: null,
    lvl: 0
  };
});


state.stemKeys = state.SONG && state.SONG.stems ? [...state.SONG.stems] : [];
}

