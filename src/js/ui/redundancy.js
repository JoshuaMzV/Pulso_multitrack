import { getAudioCtx } from '../audio/engine.js';
import { createJumpQueue } from '../audio/redundancy.js';
import { jumpTo, play } from '../audio/transport.js';
import { getAuthToken } from '../services/auth.js';
import { state } from '../state/store.js';

export function initializeRedundancy() {
  const button = document.getElementById('btnRedundancy');
  const panel = document.getElementById('redundancyPanel');
  const status = panel.querySelector('[role=status]');
  const codeInput = panel.querySelector('input');
  const sectionInput = panel.querySelector('select');
  const startButton = panel.querySelector('[data-action=start]');
  const jumpButton = panel.querySelector('[data-action=jump]');
  let session = null;

  async function request(current, action, extra = {}) {
    const sent = performance.now();
    const response = await fetch('/api/redundancy', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + getAuthToken() },
      body: JSON.stringify({ action, code: current.code, device: current.device,
        fingerprint: current.fingerprint, ...extra })
    });
    if (response.status === 404 && !response.headers.get('content-type')?.includes('json')) {
      throw new Error('Reinicia el servidor de PULSO para activar el ensayo A/B.');
    }
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    const received = performance.now();
    const roundTrip = received - sent;
    if (roundTrip < current.bestRtt) {
      current.bestRtt = roundTrip;
      current.offset = data.now - (sent + received) / 2;
    }
    return data;
  }

  const localTime = (current, serverTime) => serverTime - current.offset;

  async function receive(current, data) {
    if (session !== current) return;
    const sameSetup = state.SONG === current.song && state.bpm === current.bpm &&
      state.transposeSemitones === current.transpose;
    if (!sameSetup) throw new Error('Cambió la canción, el tempo o el tono. Abre una sala nueva.');
    codeInput.value = current.code;
    startButton.disabled = !data.primary || !data.connected || !!data.start;
    jumpButton.disabled = !data.primary || !data.connected || !state.isPlaying ||
      !data.start || data.now < data.start || !!data.jump;
    status.textContent = `${data.primary ? 'Principal' : 'Respaldo'} · ${data.connected ? 'vinculado' : 'esperando respaldo'}`;
    if (data.start && !current.start) {
      current.start = data.start;
      current.startLocal = localTime(current, data.start);
      if (state.isPlaying) throw new Error('Detén la reproducción antes de iniciar el ensayo.');
      await play({ at: state.ctx.currentTime + (current.startLocal - performance.now()) / 1000, fromBeginning: true });
    }
    if (data.jump && !current.jump && (!data.primary || data.ack)) {
      const jump = data.jump;
      const elapsed = Math.max(0, Math.floor((performance.now() - current.startLocal) / current.tickMs));
      current.queue.advance(elapsed);
      const accepted = current.queue.receive(jump);
      const section = current.sections[Number(jump.sectionId)];
      if (!accepted.ok || !section || jump.songId !== current.songId) {
        throw new Error('El salto llegó tarde o la sección no coincide.');
      }
      current.jump = jump;
      const target = current.startLocal + jump.executeAt * current.tickMs;
      current.jumpTimer = setTimeout(() => {
        const [due] = current.queue.advance(jump.executeAt);
        if (due && session === current && state.SONG === current.song && state.isPlaying) jumpTo(section.bar * 16);
      }, Math.max(0, target - performance.now()));
    }
    if (!data.primary && current.jump && !data.ack) await request(current, 'ack', { seq: current.jump.seq });
    if (current.jump) status.textContent += ' · salto programado';
  }

  async function poll(current) {
    if (session !== current) return;
    try {
      await receive(current, await request(current, 'poll'));
    } catch (error) {
      status.textContent = error.message;
      startButton.disabled = jumpButton.disabled = true;
    }
    if (session === current) current.pollTimer = setTimeout(() => poll(current), 250);
  }

  function leave() {
    if (!session) return;
    clearTimeout(session.pollTimer);
    clearTimeout(session.jumpTimer);
    session = null;
    startButton.disabled = jumpButton.disabled = true;
  }

  async function pair(action) {
    if (!state.SONG || state.audioLoading || state.isPlaying || !Object.keys(state.REAL_STEM_BUFFERS).length) {
      throw new Error('Carga una canción y detén el audio en ambos equipos.');
    }
    const ctx = getAudioCtx();
    await ctx.resume();
    if (ctx.state !== 'running') throw new Error('No se pudo activar el audio.');
    const song = state.SONG;
    const songId = String(song.folderId || song.id || song.title);
    const sections = song.sections || [];
    const media = Object.keys(state.REAL_STEM_BUFFERS).sort();
    const expected = song.backendStems?.filter(stem => stem.filename).map(stem => stem.id || stem.category || 'other') || [];
    if (!sections.length) throw new Error('La canción no tiene secciones. Agrégalas en Arranger antes de vincular.');
    const missing = expected.filter(id => !media.includes(id));
    if (missing.length) throw new Error('Pistas sin cargar: ' + missing.join(', '));
    const tracks = (song.backendStems || []).filter(stem => stem.filename)
      .map(stem => [stem.id || stem.category || 'other', stem.filename]).sort();
    const manifest = [songId, state.bpm, state.transposeSemitones, song.total16ths,
      sections.map(({ name, bar, len }) => [name, bar, len]), media, tracks];
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(manifest)));
    const fingerprint = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
    const current = { song, songId, sections, fingerprint, bpm: state.bpm, transpose: state.transposeSemitones,
      device: crypto.randomUUID(), code: codeInput.value.trim().toLowerCase(), bestRtt: Number.POSITIVE_INFINITY,
      tickMs: state.stepSec() * 1000 };
    const data = await request(current, action);
    leave();
    current.code = data.code;
    current.queue = createJumpQueue({ sessionId: data.code, showHash: fingerprint });
    current.queue.match(current.queue.hello);
    sectionInput.replaceChildren(...sections.map((section, index) => {
      const option = document.createElement('option');
      option.value = index;
      option.textContent = section.name;
      return option;
    }));
    session = current;
    await receive(current, data);
    poll(current);
  }

  button.addEventListener('click', () => panel.showModal());
  panel.addEventListener('click', async event => {
    const control = event.target.closest('[data-action]');
    if (!control) return;
    const { action } = control.dataset;
    control.disabled = true;
    try {
      if (action === 'create' || action === 'join') await pair(action);
      if (action === 'leave') {
        leave();
        status.textContent = 'Sala desvinculada.';
      }
      const current = session;
      if (action === 'start' && current) await receive(current, await request(current, 'start'));
      if (action === 'jump' && current) {
        const elapsed = performance.now() - current.startLocal;
        const executeAt = Math.ceil((elapsed + 3000) / (current.tickMs * 16)) * 16;
        await receive(current, await request(current, 'jump', { tickMs: current.tickMs,
          command: { executeAt, songId: current.songId, sectionId: sectionInput.value } }));
      }
    } catch (error) {
      status.textContent = error.message;
    } finally {
      if (action !== 'start' && action !== 'jump') control.disabled = false;
    }
  });
}
