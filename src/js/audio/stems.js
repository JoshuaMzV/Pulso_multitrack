import { state } from '../state/store.js';
import { ensureStemAudioNode, orderMixerStemKeys, getAudioDecoderContext, vClick, vKick, vHat, vSnare, vHatTo, vBass, vSubBass, vPad, vPadTo, vLeadTo, vLead } from './engine.js';
import { renderMixer, updateStemCountBadge } from '../ui/mixer.js';
import { syncChannels, applyMix } from './transport.js';
import { renderTimeline, drawWaveAll } from '../ui/timeline.js';
import { syncModernUI, drawHeroWaveform, say } from '../ui/show.js';



export function isTransposeExcludedStem(stemId) {
  const stem = state.STEMS[stemId] || {};
  const id = String(stemId || '').toLowerCase();
  const label = String(stem.label || '').toLowerCase();
  const type = String(stem.type || '').toLowerCase();
  const identity = `${id} ${label} ${type}`;
  return type === 'click' || type === 'guide' || type === 'drums' || type === 'perc' || type === 'percussion' ||
    /click|metr[oó]n|gu[ií]a|guide|talkback|drum|bater[ií]a|percusi[oó]n|kick|snare|overhead|platos?/.test(identity);
}



export function setTransposeCompensationDelay(seconds) {
  if (!state.ctx) return;
  Object.entries(state.STEMS).forEach(([stemId, stem]) => {
    if (!stem || stemId === 'master' || !isTransposeExcludedStem(stemId)) return;
    ensureStemAudioNode(stemId);
    const delay = state.STEMS[stemId]?.transposeDelay;
    if (delay) delay.delayTime.setTargetAtTime(Math.max(0, seconds), state.ctx.currentTime, 0.015);
  });
}



const pendingAudio = new Map();

export function getCachedSongAudio(song) {
  return song && window.AUDIO_CACHE[song.id || song.title];
}

export function hasRealSongAudio(song) {
  return !!(song?.backendStems || song?.downloadUrl || song?.folderId);
}

export function preloadSongAudio(song) {
  if (!hasRealSongAudio(song) || getCachedSongAudio(song)) return;
  requestSongAudio(song).catch(error => console.warn('Error al precargar pistas', error));
}

function requestSongAudio(song, report) {
  const key = song.id || song.title;
  if (getCachedSongAudio(song)) return Promise.resolve(getCachedSongAudio(song));
  if (!pendingAudio.has(key)) {
    pendingAudio.set(key, decodeSongAudio({ ...song }, report)
      .then(audio => {
        if (audio) window.AUDIO_CACHE[key] = audio;
        return audio;
      }).finally(() => pendingAudio.delete(key)));
  }
  return pendingAudio.get(key);
}

async function decodeSongAudio(song, report = () => {}) {
  const buffers = {};
  const channels = {};
  let maxDuration = 0;
  let folder = song.folderId;
  let stemsToFetch = song.backendStems;

  // El catálogo refleja los archivos importados. Un setlist antiguo puede conservar nombres del ZIP.
  const normTitle = (song.title || '').trim().toLowerCase();
  const normId = (song.id || '').trim().toLowerCase();

  if (Array.isArray(state.LOCAL_BACKEND_SONGS)) {
    const candidates = state.LOCAL_BACKEND_SONGS.filter(entry => entry.id && entry.stems?.some(stem => stem.filename));
    const sameId = id => candidates.find(entry => entry.id.trim().toLowerCase() === id);
    const matchLocal = folder ? sameId(folder.trim().toLowerCase()) :
      sameId(normId) || sameId(normTitle) ||
      candidates.find(entry => normTitle && entry.title?.trim().toLowerCase() === normTitle);
    if (matchLocal) {
      folder = matchLocal.id;
      stemsToFetch = matchLocal.stems;
      song.folderId = folder;
      song.backendStems = stemsToFetch;
    }
  }

  if (!folder && window.ALL_SETLISTS) {
    for (const sl of state.ALL_SETLISTS) {
      if (!sl || !sl.songs) continue;
      const match = sl.songs.find(s => s.folderId && s.title && (s.title.toLowerCase() === normTitle || (s.id && s.id.toLowerCase() === normId)));
      if (match) {
        folder = match.folderId;
        if (!stemsToFetch || stemsToFetch.length === 0 || !stemsToFetch[0].filename) {
          stemsToFetch = match.backendStems;
        }
        song.folderId = folder;
        song.backendStems = stemsToFetch;
        break;
      }
    }
  }

  if (!stemsToFetch && !song.downloadUrl && !folder) {
    return;
  }
  report("CARGANDO STEMS...");
  let audioCtx;
  try {
    audioCtx = getAudioDecoderContext();
  } catch (err) {
    console.error("No se pudo iniciar el AudioContext:", err);
    report("NO SE PUDO INICIAR EL AUDIO");
    return;
  }

  // CASO A: Canción disponible localmente (/songs/<folder>/<filename>)
  if (folder && stemsToFetch && stemsToFetch.length > 0 && stemsToFetch.some(st => st.filename)) {
    report("CARGANDO STEMS LOCALES...");
    const loadStem = async (stem) => {
      if (!stem.filename) return;
      try {
        let url = stem.filename;
        if (!url.startsWith('http') && !url.startsWith('/')) {
          const filename = stem.filename.split('/').map(encodeURIComponent).join('/');
          url = `/songs/${encodeURIComponent(folder)}/${filename}`;
        } else {
          const target = new URL(url, location.origin);
          if (['localhost', '127.0.0.1', '[::1]'].includes(target.hostname) && target.pathname.startsWith('/songs/')) {
            url = target.pathname + target.search;
          }
        }
        const resp = await fetch(url);
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        const arrayBuffer = await resp.arrayBuffer();
        const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer);
        
        const stemId = stem.id || stem.category || 'other';
        buffers[stemId] = audioBuffer;
        if (audioBuffer.duration > maxDuration) {
          maxDuration = audioBuffer.duration;
        }
      } catch (err) {
        console.warn(`No se pudo cargar stem local ${stem.filename}:`, err);
      }
    };
    // Limitar las descargas y decodificaciones simultáneas reduce el pico de memoria.
    let nextStem = 0;
    const loadBatch = async () => {
      while (nextStem < stemsToFetch.length) {
        await loadStem(stemsToFetch[nextStem++]);
      }
    };
    await Promise.all([loadBatch(), loadBatch()]);
  } 

  // CASO B: Canción desde la NUBE (descarga directa del ZIP o fallback si CASO A no cargó stems)
  if (Object.keys(buffers).length === 0 && song.downloadUrl && window.JSZip) {
    try {
      let blob = null;
      // Verificar si ya existe en almacenamiento local (IndexedDB)
      if (state.CloudStorageCache) {
        blob = await state.CloudStorageCache.getSongZipBlob(song.id, song.title);
        if (blob) {
          console.log("¡Cargando stems desde almacenamiento local (IndexedDB) para:", song.title);
          report("CARGANDO DESDE ALMACENAMIENTO LOCAL...");
        }
      }

      // Si no está en caché local, descargar por única vez desde la nube
      if (!blob) {
        report("DESCARGANDO MULTITRACK DE LA NUBE (1 SOLA VEZ)...");
        const downloadTarget = song.downloadUrl + (song.downloadUrl.includes('?') ? '&' : '?') + 't=' + Date.now();
        console.log("Descargando ZIP de la nube:", downloadTarget);
        const resp = await fetch(downloadTarget, { cache: 'no-store' });
        if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
        blob = await resp.blob();

        // Guardar permanentemente en IndexedDB para no volver a descargar
        if (state.CloudStorageCache) {
          await state.CloudStorageCache.saveSongZipBlob(song.id, song.title, blob);
          if (window.LOCAL_DOWNLOADED_TITLES && song.title) {
            state.LOCAL_DOWNLOADED_TITLES.add(song.title.toLowerCase());
          }
          console.log("¡Canción guardada permanentemente en almacenamiento local!");
        }
      }
      
      report("DESCOMPRIMIENDO STEMS...");
      const zip = await JSZip.loadAsync(blob);
      const audioEntries = [];
      
      zip.forEach((path, entry) => {
        if (!entry.dir) {
          const lower = entry.name.toLowerCase();
          if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.flac') || lower.endsWith('.ogg') || lower.endsWith('.m4a')) {
            const fname = entry.name.split('/').pop();
            if (!fname.startsWith('.') && !fname.startsWith('__MACOSX')) {
              audioEntries.push({ entry, name: fname });
            }
          }
        }
      });

      report(`DECODIFICANDO ${audioEntries.length} PISTAS DE AUDIO...`);
      const decodePromises = audioEntries.map(async (item) => {
        try {
          const ab = await item.entry.async("arraybuffer");
          const audioBuffer = await audioCtx.decodeAudioData(ab);
            
          const lowerName = item.name.toLowerCase();
          let targetStemId = null;
          
          if (song.backendStems) {
            const found = song.backendStems.find(st => (st.original && st.original.toLowerCase() === lowerName) || (st.filename && st.filename.toLowerCase().includes(lowerName)));
            if (found) targetStemId = found.id || found.category;
          }

          if (!targetStemId) {
            let cat = 'other';
            let label = item.name.replace(/\.[^/.]+$/, "").substring(0, 12).toUpperCase();
            if (lowerName.includes('click') || lowerName.includes('metr')) { cat = 'click'; label = 'CLICK'; }
            else if (lowerName.includes('guide') || lowerName.includes('guia') || lowerName.includes('cue')) { cat = 'guide'; label = 'GUÍA'; }
            else if (lowerName.includes('drum') || lowerName.includes('bater') || lowerName.includes('snare') || lowerName.includes('kick') || lowerName.includes('perc')) { cat = 'drums'; label = item.name.replace(/\.[^/.]+$/, "").substring(0, 12).toUpperCase(); }
            else if (lowerName.includes('bass') || lowerName.includes('bajo')) { cat = 'bass'; label = 'BAJO'; }
            else if (lowerName.includes('key') || lowerName.includes('piano') || lowerName.includes('organ') || lowerName.includes('synth') || lowerName.includes('tecl')) { cat = 'keys'; label = item.name.replace(/\.[^/.]+$/, "").substring(0, 12).toUpperCase(); }
            else if (lowerName.includes('pad') || lowerName.includes('ambient') || lowerName.includes('colchon')) { cat = 'pad'; label = 'PADS'; }
            else if (lowerName.includes('guit') || lowerName.includes('eg ') || lowerName.includes('eg1') || lowerName.includes('eg2') || lowerName.includes('acoustic')) { cat = 'guitars'; label = item.name.replace(/\.[^/.]+$/, "").substring(0, 12).toUpperCase(); }
            else if (lowerName.includes('vox') || lowerName.includes('vocal') || lowerName.includes('choir') || lowerName.includes('coro')) { cat = 'vocals'; label = item.name.replace(/\.[^/.]+$/, "").substring(0, 12).toUpperCase(); }

            let baseId = cat;
            targetStemId = cat;
            let counter = 1;
            while (buffers[targetStemId]) {
              counter++;
              targetStemId = `${baseId}_${counter}`;
            }
            if (!channels[targetStemId]) {
              channels[targetStemId] = {
                label: label,
                gain: 0.8,
                def: 0.8,
                type: cat,
                muted: false,
                solo: false,
                node: null,
                ana: null,
                lvl: 0
              };
            }
          }

          buffers[targetStemId] = audioBuffer;
          if (audioBuffer.duration > maxDuration) {
            maxDuration = audioBuffer.duration;
          }
        } catch (decErr) {
          console.error(`Error decodificando audio de ${item.name}:`, decErr);
        }
      });
      await Promise.all(decodePromises);
    } catch (zipErr) {
      console.error("Error cargando multitrack de la nube:", zipErr);
      report("ERROR AL DESCARGAR DE LA NUBE");
    }
  }

  if (Object.keys(buffers).length) {
    const expected = stemsToFetch?.filter(stem => stem.filename);
    const complete = !expected?.length || expected.every(stem => buffers[stem.id || stem.category]);
    return { buffers, channels, maxDuration, complete, folder: song.folderId, backendStems: song.backendStems };
  }
}

export function loadRealStems(song) {
  const session = ++state.currentLoadSession;
  const led = document.getElementById('runLed');
  function setStatus(status, label) {
    if (!led) return;
    led.dataset.load = status;
    led.title = label;
    led.setAttribute('aria-label', label);
  }
  if (!hasRealSongAudio(song)) {
    state.REAL_STEM_BUFFERS = {};
    state.audioLoading = false;
    setStatus('idle', 'Sin pistas de audio');
    return Promise.resolve();
  }
  function activate(audio) {
    if (session !== state.currentLoadSession || state.SONG !== song) return;
    state.audioLoading = false;
    state.REAL_STEM_BUFFERS = audio?.buffers || {};
    if (!audio) {
      setStatus('error', 'No se pudieron cargar las pistas');
      say('NO SE PUDIERON CARGAR STEMS');
      return;
    }
    if (audio.folder) song.folderId = audio.folder;
    if (audio.backendStems) song.backendStems = audio.backendStems;
    for (const meta of audio.backendStems || []) {
      const id = meta.id || meta.category;
      if (!id) continue;
      const channel = state.STEMS[id] ||= { gain: .8, def: .8, muted: false, solo: false };
      channel.label = meta.label || id.toUpperCase();
      channel.type = meta.category || id;
    }
    for (const [id, channel] of Object.entries(audio.channels || {})) {
      state.STEMS[id] ||= { ...channel };
    }
    const { maxDuration } = audio;
  // Asegurar que los nodos de audio existan en STEMS
  Object.keys(state.REAL_STEM_BUFFERS).forEach(sId => {
    if (!state.STEMS[sId]) {
      state.STEMS[sId] = {
        label: sId.toUpperCase(),
        gain: 0.8,
        def: 0.8,
        type: sId,
        muted: false,
        solo: false,
        node: null,
        ana: null,
        lvl: 0
      };
    }
    ensureStemAudioNode(sId);
  });

  if (state.SONG === song && Object.keys(state.REAL_STEM_BUFFERS).length > 0) {
    song.stems = Object.keys(state.REAL_STEM_BUFFERS);
    state.stemKeys = orderMixerStemKeys(song.stems);
    renderMixer();
    syncChannels();
    applyMix();
  }

  if (maxDuration > 0) {
    const sSec = 60 / song.bpm / 4;
    song.total16ths = Math.ceil(maxDuration / sSec);
    if (state.SONG === song) {
      renderTimeline(); syncModernUI(0);
      updateStemCountBadge();
      drawHeroWaveform();
      drawWaveAll();
    }
  }

    setStatus('ready', 'Pistas cargadas');
    say('LISTO');
  }
  const cached = getCachedSongAudio(song);
  if (cached) {
    activate(cached);
    return Promise.resolve(cached);
  }
  state.REAL_STEM_BUFFERS = {};
  state.audioLoading = true;
  setStatus('loading', 'Cargando pistas');
  say('CARGANDO STEMS...');
  return requestSongAudio(song, message => {
    if (session === state.currentLoadSession) say(message);
  }).then(activate, () => activate(null));
}



export async function loadSignalsmithStretch() {
  if (!state.signalsmithStretchFactoryPromise) {
    state.signalsmithStretchFactoryPromise = import('../../vendor/SignalsmithStretch.mjs')
      .then(module => module.default)
      .catch(error => {
        state.signalsmithStretchFactoryPromise = null;
        throw error;
      });
  }
  return state.signalsmithStretchFactoryPromise;
}



export function destroyRealStretchRoutes() {
  state.REAL_STRETCH_ROUTES.forEach(route => {
    try { route.stretch.schedule({active: false, output: state.ctx.currentTime}).catch(() => {}); } catch (_) {}
    [route.inputMerger, route.stretch, route.outputSplitter, ...route.outputMergers].forEach(node => {
      try { node.disconnect(); } catch (_) {}
    });
  });
  state.REAL_STRETCH_ROUTES = [];
  state.REAL_STRETCH_ROUTE_SONG = null;
  state.REAL_STRETCH_LATENCY = 0;
}



export async function ensureRealStretchRoutes() {
  const melodicStemIds = Object.keys(state.REAL_STEM_BUFFERS).filter(stemId =>
    state.STEMS[stemId]?.node && !isTransposeExcludedStem(stemId)
  );
  if (state.transposeSemitones === 0 || !melodicStemIds.length) {
    state.REAL_STRETCH_LATENCY = 0;
    setTransposeCompensationDelay(0);
    return [];
  }

  const songKey = state.SONG?.id || state.SONG?.folderId || state.SONG?.title || 'active-song';
  const routeMatches = state.REAL_STRETCH_ROUTE_SONG === songKey &&
    state.REAL_STRETCH_ROUTES.flatMap(route => route.stemIds).join('|') === melodicStemIds.join('|');
  if (!routeMatches) {
    destroyRealStretchRoutes();
    const SignalsmithStretch = await loadSignalsmithStretch();
    for (let offset = 0; offset < melodicStemIds.length; offset += state.TRANSPOSE_GROUP_STEMS) {
      const stemIds = melodicStemIds.slice(offset, offset + state.TRANSPOSE_GROUP_STEMS);
      const channelCount = stemIds.length * 2;
      const inputMerger = state.ctx.createChannelMerger(channelCount);
      const stretch = await SignalsmithStretch(state.ctx, {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        channelCount,
        channelCountMode: 'explicit',
        channelInterpretation: 'discrete',
        outputChannelCount: [channelCount]
      });
      await stretch.configure({preset: 'cheaper'});
      const outputSplitter = state.ctx.createChannelSplitter(channelCount);
      inputMerger.connect(stretch);
      stretch.connect(outputSplitter);

      const outputMergers = [];
      const stemChannels = {};
      stemIds.forEach((stemId, stemIndex) => {
        const firstChannel = stemIndex * 2;
        const stemOutput = state.ctx.createChannelMerger(2);
        stemOutput.channelInterpretation = 'discrete';
        outputSplitter.connect(stemOutput, firstChannel, 0);
        outputSplitter.connect(stemOutput, firstChannel + 1, 1);
        stemChannels[stemId] = {firstChannel};
        outputMergers.push(stemOutput);
      });
      state.REAL_STRETCH_ROUTES.push({stemIds, stemChannels, inputMerger, stretch, outputSplitter, outputMergers, connected: false});
    }
    state.REAL_STRETCH_ROUTE_SONG = songKey;
  }

  state.REAL_STRETCH_ROUTES.forEach(route => {
    if (route.connected) return;
    route.stemIds.forEach((stemId, index) => route.outputMergers[index].connect(state.STEMS[stemId].node));
    route.connected = true;
  });
  const latencyValues = await Promise.all(state.REAL_STRETCH_ROUTES.map(route => route.stretch.latency()));
  state.REAL_STRETCH_LATENCY = Math.max(0, ...latencyValues);
  setTransposeCompensationDelay(state.REAL_STRETCH_LATENCY);
  return state.REAL_STRETCH_ROUTES;
}



export async function playRealStems(startPosSeconds, delaySeconds = 0, startTime = null, replace = false,
  stillCurrent = () => true) {
  if (!state.ctx) return;
  const previousSources = state.REAL_STEM_SOURCES;
  const shiftedRoutes = state.transposeSemitones !== 0 ? await ensureRealStretchRoutes() : [];
  if (!stillCurrent()) return;
  if (!shiftedRoutes.length) setTransposeCompensationDelay(0);

  const routeByStem = new Map();
  shiftedRoutes.forEach(route => route.stemIds.forEach(stemId => routeByStem.set(stemId, route)));
  const sourceStart = Number.isFinite(startTime) ? startTime : state.ctx.currentTime + 0.1 + delaySeconds;
  await Promise.all(shiftedRoutes.map(route => route.stretch.schedule({
    active: true,
    semitones: state.transposeSemitones,
    output: sourceStart
  })));
  if (!stillCurrent()) return;

  if (replace) {
    if (!state.isPlaying || previousSources !== state.REAL_STEM_SOURCES) return;
    Object.values(previousSources).forEach(source => source.stop(sourceStart));
    state.REAL_STEM_SOURCES = {};
  }
  for (const stId of Object.keys(state.REAL_STEM_BUFFERS)) {
    if (!state.STEMS[stId]?.node) continue;
    const source = state.ctx.createBufferSource();
    source.buffer = state.REAL_STEM_BUFFERS[stId];
    const route = routeByStem.get(stId);
    let splitter;
    if (route) {
      const firstChannel = route.stemChannels[stId].firstChannel;
      if (source.buffer.numberOfChannels === 1) {
        source.connect(route.inputMerger, 0, firstChannel);
        source.connect(route.inputMerger, 0, firstChannel + 1);
      } else {
        splitter = state.ctx.createChannelSplitter(2);
        source.connect(splitter);
        splitter.connect(route.inputMerger, 0, firstChannel);
        splitter.connect(route.inputMerger, 1, firstChannel + 1);
        state.REAL_STEM_SOURCE_SPLITTERS.push(splitter);
      }
    } else {
      source.connect(state.STEMS[stId].node);
    }
    source.start(sourceStart, startPosSeconds);
    state.REAL_STEM_SOURCES[stId] = source;
    state.addNode(source);
    if (splitter) source.addEventListener('ended', () => {
      splitter.disconnect();
      const index = state.REAL_STEM_SOURCE_SPLITTERS.indexOf(splitter);
      if (index >= 0) state.REAL_STEM_SOURCE_SPLITTERS.splice(index, 1);
    }, { once: true });
  }
  applyMix();
}



export function stopRealStems() {
  if (!state.ctx) return;
  const now = state.ctx.currentTime;
  for (const source of Object.values(state.REAL_STEM_SOURCES)) {
    try { source.stop(now); } catch (_) {}
  }
  state.REAL_STEM_SOURCE_SPLITTERS.forEach(splitter => { try { splitter.disconnect(); } catch (_) {} });
  state.REAL_STEM_SOURCE_SPLITTERS = [];
  state.REAL_STEM_SOURCES = {};
  state.REAL_STRETCH_ROUTES.forEach(route => {
    route.stretch.schedule({active: false, output: now + 0.01}).catch(() => {});
    if (route.connected) {
      route.outputMergers.forEach(output => { try { output.disconnect(); } catch (_) {} });
      route.connected = false;
    }
  });
}



export async function restartRealStemsAt(positionSeconds) {
  if (!state.ctx || !state.isPlaying || !Object.keys(state.REAL_STEM_BUFFERS).length) return false;
  const songAtStart = state.SONG;
  try {
    if (state.transposeSemitones !== 0) await ensureRealStretchRoutes();
    else setTransposeCompensationDelay(0);
    if (state.SONG !== songAtStart) return false;

    const restartAt = state.ctx.currentTime + 0.12;
    const resumeMasterAt = restartAt + state.REAL_STRETCH_LATENCY + 0.035;
    if (state.kill) {
      const now = state.ctx.currentTime;
      state.kill.gain.cancelScheduledValues(now);
      state.kill.gain.setValueAtTime(state.kill.gain.value, now);
      state.kill.gain.linearRampToValueAtTime(0.0001, restartAt);
    }
    stopRealStems();
    await playRealStems(positionSeconds, 0, restartAt);
    if (state.kill) {
      state.kill.gain.setValueAtTime(0.0001, resumeMasterAt - 0.01);
      state.kill.gain.linearRampToValueAtTime(1, resumeMasterAt);
    }
    return true;
  } catch (error) {
    if (state.kill) state.kill.gain.setTargetAtTime(1, state.ctx.currentTime, 0.015);
    console.error('No se pudo reiniciar el audio transpuesto:', error);
    say('NO SE PUDO APLICAR LA TRANSPOSICIÓN');
    return false;
  }
}



export function vClickTo(t, acc, targetNode) {
  if (!state.ctx || !targetNode) return;
  const o = state.ctx.createOscillator(), g = state.ctx.createGain();
  o.type = 'square'; o.frequency.value = acc ? 1400 : 980;
  g.gain.setValueAtTime(.15, t); g.gain.exponentialRampToValueAtTime(.0001, t + .03);
  o.connect(g); g.connect(targetNode); o.start(t); o.stop(t + .04); state.addNode(o);
}


/* ---------- Secuenciador ---------- */

export function scheduleStep(t16, t) {
  if (state.SONG.backendStems || state.SONG.downloadUrl || Object.keys(state.REAL_STEM_BUFFERS).length > 0) return; // Si es una canción real, no usar el sintetizador (excepto click si es necesario)
  
  if (t16 < 0) {
    if (t16 % 4 === 0) vClick(t, t16 % 16 === 0);
    return;
  }
  const pos = ((t16 % 128) + 128) % 128, bar = pos >> 4, step = pos & 15, sec = bar >> 1;
  if (step % 4 === 0) vClick(t, step === 0); // Click con acento en el beat 1

  // Batería Base
  if (sec === 0) {
    if (step === 0 || step === 8) vKick(t, .7);
    if (step === 0) vHat(t, .32, .4);
    if (step % 2 === 0) vHat(t, .2, .05);
  } else if (sec === 1) {
    if (step === 0 || step === 8) vKick(t, .9);
    if (step === 4 || step === 12) vSnare(t, .65);
    if (step % 2 === 0) vHat(t, .38, .05);
  } else if (sec === 2) {
    if (step === 0 || step === 6 || step === 8) vKick(t, .95);
    if (step === 4 || step === 12) vSnare(t, .85);
    if (step === 15 && bar === 5) vSnare(t, .45);
    vHat(t, step % 2 === 0 ? .45 : .2, .04);
  } else {
    if (bar === 6) {
      if (step === 0 || step === 8) vKick(t, .75);
      if (step % 2 === 0) vHat(t, .18, .08);
    } else {
      if (step === 0) vKick(t, .9);
      if (step >= 8) vSnare(t, .2 + step * .05);
    }
  }

  // Percusión auxiliar, Loop FX y Overheads
  if (state.STEMS.drums_oh?.node && (step % 2 === 0 || (sec >= 2 && step % 4 === 2))) {
    vHatTo(t, .24, .14, state.STEMS.drums_oh.node);
  }
  if (state.STEMS.perc?.node && (step % 4 === 2 || (sec >= 2 && step % 2 === 1))) {
    vHatTo(t, .26, .05, state.STEMS.perc.node);
  }
  if (state.STEMS.loop_fx?.node && sec >= 1 && step % 2 === 0) {
    vHatTo(t, .18, .04, state.STEMS.loop_fx.node);
  }

  // Bajo y Sub Bass
  const root = state.SONG.bass[bar];
  let notes = null;
  if (sec === 0) notes = [[0, 1, 7], [8, 1, 7]];
  else if (sec < 3) notes = [[0, 1, 3], [6, 1, 2], [8, 1, 3], [11, 2, 3], [14, 1, 2]];
  else notes = bar === 6 ? [[0, 1, 12]] : [[0, 1, 6], [8, 1, 6]];
  for (const [st, oc, du] of notes) {
    if (st === step) {
      vBass(t, root * oc, du * state.stepSec() * .95, .5);
      if (state.STEMS.sub_bass?.node) vSubBass(t, (root * oc) * .5, du * state.stepSec() * .95, .4);
    }
  }

  // Teclas, Pads, Strings, Organ, Coros
  if (step === 0) {
    vPad(t, state.SONG.pads[bar], 16 * state.stepSec() * .98, sec === 0 ? .09 : .16);
    if (state.STEMS.pad_amb?.node) vPadTo(t, state.SONG.pads[bar], 16 * state.stepSec() * .98, .08, state.STEMS.pad_amb.node);
    if (state.STEMS.strings?.node && sec >= 1) vPadTo(t, state.SONG.pads[bar], 16 * state.stepSec() * .98, .10, state.STEMS.strings.node);
    if (state.STEMS.organ?.node && sec >= 2) vPadTo(t, state.SONG.pads[bar], 16 * state.stepSec() * .98, .08, state.STEMS.organ.node);
    if (state.STEMS.bgv_choir?.node && sec >= 2) vPadTo(t, state.SONG.pads[bar], 16 * state.stepSec() * .98, .09, state.STEMS.bgv_choir.node);
  }

  // Guitarras acústicas y eléctricas
  const chordNotes = state.SONG.pads[bar];
  if (chordNotes) {
    if (step % 4 === 0 && state.STEMS.guit_ac?.node) {
      vLeadTo(t, chordNotes[0] * 1.5, state.stepSec() * 2.5, .15, state.STEMS.guit_ac.node);
    }
    if (step % 4 === 2 && state.STEMS.guit_ac2?.node) {
      vLeadTo(t, (chordNotes[1] || chordNotes[0]) * 1.5, state.stepSec() * 2.5, .15, state.STEMS.guit_ac2.node);
    }
    if (step % 2 === 0 && state.STEMS.guit_el1?.node && sec >= 1) {
      vLeadTo(t, chordNotes[step % 3] * 1.2, state.stepSec() * 1.4, .18, state.STEMS.guit_el1.node);
    }
    if (step === 0 && state.STEMS.guit_el2?.node && sec >= 2) {
      vPadTo(t, chordNotes, 16 * state.stepSec() * .9, .14, state.STEMS.guit_el2.node);
    }
  }

  // Melodía principal, Voces, Metales y Sintetizadores
  for (const [st, f, len] of state.SONG.melody) {
    if (st === pos) {
      vLead(t, f, len * state.stepSec() * .9, .3);
      if (state.STEMS.vox_lead?.node) vLeadTo(t, f, len * state.stepSec() * .9, .28, state.STEMS.vox_lead.node);
      if (state.STEMS.vox_harm?.node) vLeadTo(t, f * 1.25, len * state.stepSec() * .9, .18, state.STEMS.vox_harm.node);
      if (state.STEMS.synth_lead?.node) vLeadTo(t, f * 2, len * state.stepSec() * .9, .16, state.STEMS.synth_lead.node);
      if (state.STEMS.brass?.node && sec === 3) vLeadTo(t, f * .5, len * state.stepSec() * .9, .24, state.STEMS.brass.node);
    }
  }

  // Talkback cue
  if (step === 0 && bar % 2 === 0 && state.STEMS.talkback?.node) {
    vClickTo(t, false, state.STEMS.talkback.node);
  }
}

export function initializeStems() {

state.REAL_STEM_BUFFERS = {};

state.REAL_STEM_SOURCES = {};

state.REAL_STEM_SOURCE_SPLITTERS = [];

state.REAL_STRETCH_ROUTES = [];

state.REAL_STRETCH_ROUTE_SONG = null;

state.REAL_STRETCH_LATENCY = 0;

state.signalsmithStretchFactoryPromise = null;

state.audioLoading = false;

state.currentLoadSession = 0;

state.transposeTargetKey = null;

state.transposeSemitones = 0;


state.TRANSPOSE_GROUP_STEMS = 8;


window.AUDIO_CACHE = window.AUDIO_CACHE || {};
}

