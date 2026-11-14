import { state } from '../state/store.js';

const routes = new Map();
const modules = new WeakMap();
const drafts = new WeakMap();

export function clearEqRoutes() {
  routes.clear();
}

export function registerEqRoute(id, input, output) {
  input.connect(output);
  routes.set(id, { input, output });
}

function storageKey(id) {
  const song = state.SONG;
  const identity = id === 'master' ? state.ctx?.sinkId || 'default'
    : song?.id || song?.folderId || song?.downloadUrl || [song?.title, song?.artist];
  return 'pulso-eq-v1:' + JSON.stringify([id, identity]);
}

export function defaultEq(id) {
  const frequencies = id === 'master' ? [80, 200, 500, 1500, 4000, 10000]
    : [100, 400, 2500, 10000];
  return {
    bypass: false, outputDb: 0,
    bands: frequencies.map((frequency, i) => ({
      frequency, gainDb: 0, q: 1, shape: i === 0 ? 0 : i === frequencies.length - 1 ? 2 : 1
    }))
  };
}

export function readEq(id) {
  const defaults = defaultEq(id);
  const numeric = (value, fallback, min, max) => Number.isFinite(value)
    ? Math.max(min, Math.min(max, value)) : fallback;
  try {
    const saved = drafts.get(state.SONG)?.get(id) || state.SONG?.mix?.[id]?.eq ||
      JSON.parse(localStorage.getItem(storageKey(id)));
    return {
      bypass: saved?.bypass === true,
      outputDb: numeric(saved?.outputDb, 0, -12, 12),
      bands: defaults.bands.map((band, i) => ({
        shape: band.shape,
        frequency: numeric(saved?.bands?.[i]?.frequency, band.frequency, 20, 20000),
        gainDb: numeric(saved?.bands?.[i]?.gainDb, 0, -12, 12),
        q: numeric(saved?.bands?.[i]?.q, 1, .1, 12)
      }))
    };
  } catch (_) { return defaults; }
}

export function saveEq(id, settings) {
  if (state.SONG) {
    if (!drafts.has(state.SONG)) drafts.set(state.SONG, new Map());
    drafts.get(state.SONG).set(id, settings);
  }
  localStorage.setItem(storageKey(id), JSON.stringify(settings));
}

export async function applyEq(id, settings) {
  const route = routes.get(id);
  if (!route) return;
  if (!route.pending && !route.node && (settings.bypass || (!settings.outputDb && settings.bands.every(band => !band.gainDb)))) return;
  if (!route.pending && !route.node) {
    const ctx = route.input.context;
    if (!modules.has(ctx)) {
      modules.set(ctx, Promise.all([
        ctx.audioWorklet.addModule(new URL('./eq-worklet.js', import.meta.url)),
        fetch(new URL('../../assets/pulso-eq.wasm', import.meta.url)).then(response => {
          if (!response.ok) throw new Error('EQ WASM no disponible');
          return response.arrayBuffer();
        }).then(bytes => WebAssembly.compile(bytes))
      ]).catch(error => {
        modules.delete(ctx);
        throw error;
      }));
    }
    route.pending = modules.get(ctx).then(([, module]) => {
      const node = new window.AudioWorkletNode(ctx, 'pulso-eq', {
        outputChannelCount: [2], processorOptions: { module }
      });
      node.onprocessorerror = () => {
        route.input.disconnect(node);
        node.disconnect();
        route.input.connect(route.output);
        route.node = null;
      };
      node.connect(route.output);
      route.input.connect(node);
      route.input.disconnect(route.output);
      route.node = node;
    }).finally(() => { route.pending = null; });
  }
  route.latest = settings;
  if (route.pending) await route.pending;
  route.node?.port.postMessage(route.latest);
}

export function restoreEq(id) {
  applyEq(id, readEq(id)).catch(error => console.warn('EQ no disponible', error));
}
