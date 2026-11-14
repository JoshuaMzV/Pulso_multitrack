const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../src/js/audio/redundancy.js'));
const protocol = import('data:text/javascript;base64,' + source.toString('base64'));

test('el respaldo distingue material distinto y ejecuta el salto una sola vez sin recibir más mensajes', async () => {
  const { fingerprintShow, createJumpQueue } = await protocol;
  const song = {
    id: 'song-1', bpm: 120, meter: '4/4', total16ths: 128,
    sections: [{ id: 'chorus', bar: 4, len: 4 }],
    audio: { click: 'a'.repeat(64), guide: 'b'.repeat(64) }
  };
  const showHash = await fingerprintShow([song]);
  assert.equal(showHash, await fingerprintShow([{ ...song, audio: { guide: song.audio.guide, click: song.audio.click } }]));
  const differentHash = await fingerprintShow([{ ...song, audio: { ...song.audio, guide: 'c'.repeat(64) } }]);
  assert.notEqual(showHash, differentHash);
  assert.notEqual(showHash, await fingerprintShow([{ ...song, bpm: 121 }]));

  const follower = createJumpQueue({ sessionId: 'show-1', showHash });
  const jump = { sessionId: 'show-1', type: 'jump', seq: 1, executeAt: 64, songId: 'song-1', sectionId: 'chorus' };
  assert.equal(follower.match({ ...follower.hello, showHash: differentHash }), false);
  assert.equal(follower.receive(jump).ok, false);
  assert.equal(follower.match({ ...follower.hello }), true);
  assert.equal(follower.receive({ ...jump, seq: 2 }).reason, 'sequence');
  assert.deepEqual(follower.receive(jump), { ok: true, sessionId: 'show-1', seq: 1 });
  assert.equal(follower.receive({ ...jump }).ok, true);
  assert.equal(follower.receive({ ...jump, sectionId: 'verse' }).reason, 'conflict');
  assert.deepEqual(follower.advance(63), []);
  // A deja de responder: B solo depende del reloj de sesión para consumir su cola.
  assert.deepEqual(follower.advance(64), [jump]);
  assert.deepEqual(follower.advance(80), []);
  assert.equal(follower.receive({ ...jump, seq: 2 }).reason, 'late');
  assert.throws(() => follower.advance(32), /retroceder/);
});
