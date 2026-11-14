const version = 1;
const digestPattern = /^[a-f0-9]{64}$/;
const isTick = value => Number.isSafeInteger(value) && value >= 0;

// Los digests corresponden a los bytes locales, incluidos Click y Guía.
export async function fingerprintShow(songs) {
  const manifest = songs.map(({ id, bpm, meter, total16ths, sections, audio }) => {
    const tracks = Object.entries(audio).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0);
    if (!tracks.length || tracks.some(([, digest]) => typeof digest !== 'string' || !digestPattern.test(digest))) {
      throw new Error('Falta verificar el audio local');
    }
    return [id, bpm, meter, total16ths, sections.map(({ id, bar, len }) => [id, bar, len]), tracks];
  });
  const bytes = new TextEncoder().encode(JSON.stringify(manifest));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

export function createJumpQueue({ sessionId, showHash }) {
  if (typeof sessionId !== 'string' || !sessionId || typeof showHash !== 'string' || !digestPattern.test(showHash)) {
    throw new Error('Sesión de respaldo inválida');
  }
  const accepted = new Map();
  const pending = [];
  let ready = false;
  let tick = 0;
  let lastExecutionTick = 0;
  const hello = Object.freeze({ version, sessionId, showHash });

  return {
    hello,
    match(peer) {
      ready = peer?.version === version && peer.sessionId === sessionId && peer.showHash === showHash;
      return ready;
    },
    receive(command) {
      if (!ready || command?.sessionId !== sessionId || command.type !== 'jump') {
        return { ok: false, reason: 'session' };
      }
      const { seq, executeAt, songId, sectionId } = command;
      if (!isTick(seq) || seq === 0 || !isTick(executeAt) ||
          typeof songId !== 'string' || !songId || typeof sectionId !== 'string' || !sectionId) {
        return { ok: false, reason: 'invalid' };
      }
      const previous = accepted.get(seq);
      if (previous) {
        return previous.executeAt === executeAt && previous.songId === songId && previous.sectionId === sectionId
          ? { ok: true, sessionId, seq }
          : { ok: false, reason: 'conflict' };
      }
      if (seq !== accepted.size + 1) return { ok: false, reason: 'sequence' };
      if (executeAt <= tick || executeAt <= lastExecutionTick) return { ok: false, reason: 'late' };
      const jump = Object.freeze({ sessionId, type: 'jump', seq, executeAt, songId, sectionId });
      accepted.set(seq, jump);
      pending.push(jump);
      lastExecutionTick = executeAt;
      return { ok: true, sessionId, seq };
    },
    // El reloj de sesión avanza incluso cuando la posición de la canción vuelve atrás.
    advance(nextTick) {
      if (!isTick(nextTick) || nextTick < tick) throw new Error('El reloj de sesión no puede retroceder');
      tick = nextTick;
      const due = [];
      while (pending[0]?.executeAt <= tick) due.push(pending.shift());
      return due;
    }
  };
}
