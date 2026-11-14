const { test, expect } = require('@playwright/test');

function audioFixture(seconds = 8) {
  const samples = 44100 * seconds;
  const data = Buffer.alloc(44 + samples * 2);
  data.write('RIFF'); data.writeUInt32LE(data.length - 8, 4); data.write('WAVEfmt ', 8);
  data.writeUInt32LE(16, 16); data.writeUInt16LE(1, 20); data.writeUInt16LE(1, 22);
  data.writeUInt32LE(44100, 24); data.writeUInt32LE(88200, 28); data.writeUInt16LE(2, 32);
  data.writeUInt16LE(16, 34); data.write('data', 36); data.writeUInt32LE(samples * 2, 40);
  for (let i = 0; i < samples; i++) data.writeInt16LE(Math.round(1000 * Math.sin(2 * Math.PI * 220 * i / 44100)), 44 + i * 2);
  return data;
}

async function fixture(page, seconds = 8) {
  const body = audioFixture(seconds);
  await page.route('**/songs/regression/**', route => route.fulfill({ contentType: 'audio/wav', body }));
  // Estas pruebas nunca escriben en setlists reales ni acceden al catálogo remoto.
  await page.route('**/api/setlists', route => route.fulfill({ json: [] }));
  await page.goto('/');
  await page.waitForFunction(() => typeof window.selectSong === 'function');
  await page.evaluate(async () => {
    const { state } = await import('/js/state/store.js');
    window.CURRENT_USER = { id: 'regression', username: 'Prueba', role: 'admin' };
    window.closeAuthModal();
    const stems = ['keys', 'drums', 'click', 'guide'];
    state.SONGS_DATA = [0, 1].map(i => ({ id: 'regression-' + i, title: 'Prueba ' + i, artist: 'Prueba',
      bpm: 120, key: i ? 'G' : 'E', total16ths: 64, stems,
      folderId: 'regression', backendStems: stems.map(id => ({ id, category: id, filename: id + '.wav' })),
      sections: [{ name: 'INTRO', bar: 0, len: 2 }, { name: 'VERSO', bar: 2, len: 2 }] }));
    state.ALL_SETLISTS = [{ id: 'regression', name: 'Prueba', songs: state.SONGS_DATA }];
    window.selectSong(0);
    window.renderEditionSongList();
  });
  await page.waitForFunction(async () => {
    const { state } = await import('/js/state/store.js');
    return !state.audioLoading && Object.keys(state.REAL_STEM_BUFFERS).length === 4;
  });
}

test('Master compartido deja clic y guía fuera de la mezcla instrumental', async ({ page }) => {
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  const show = page.locator('#moMasterSlider');
  const edition = page.getByRole('slider', { name: 'Nivel Master', exact: true });
  await page.evaluate(() => window.play({ fromBeginning: true }));
  await edition.press('ArrowDown');
  const displayedDb = await edition.getAttribute('aria-valuenow');
  await expect(show).toHaveValue(String(Number(displayedDb)));
  await show.evaluate(slider => {
    slider.value = '-15';
    slider.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await expect(edition).toHaveAttribute('aria-valuenow', '-15.0');
  await page.getByRole('button', { name: 'Silenciar Master' }).click();
  await expect.poll(() => page.evaluate(async () => {
    const { state } = await import('/js/state/store.js');
    return state.masterG?.gain.value < .001 &&
      state.STEMS.click.destination === state.cueOutput &&
      state.STEMS.guide.destination === state.cueOutput &&
      state.STEMS.keys.destination === state.masterG;
  })).toBe(true);
});

for (const mode of ['stop', 'instant', 'overlap']) {
  test(`Transición ${mode} al final natural`, async ({ page }) => {
    await fixture(page, mode === 'overlap' ? 10 : 1);
    await page.locator('#btnViewEdition').click();
    const trigger = page.getByRole('button', { name: 'Transición de la canción 1 a la 2: Con pausa' });
    await trigger.click();
    const options = page.getByRole('group', { name: 'Tipo de transición' });
    await expect(options.getByRole('button', { name: 'Con pausa' })).toHaveAttribute('aria-pressed', 'true');
    const label = { stop: 'Con pausa', instant: 'Al terminar', overlap: 'Traslape con fundido' }[mode];
    await options.getByRole('button', { name: label }).click();
    await expect(page.getByRole('button', { name: `Transición de la canción 1 a la 2: ${label}` }))
      .toHaveAttribute('aria-expanded', 'false');
    const result = await page.evaluate(async () => {
      const { state } = await import('/js/state/store.js');
      await window.play({ fromBeginning: true });
      const anchor = state.anchor.time;
      const oldMusic = state.musicOutput;
      const oldCue = state.cueOutput;
      while (state.currentSongIdx === 0 && state.ctx.currentTime < anchor + 4) {
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      await new Promise(resolve => setTimeout(resolve, 300));
      return { index: state.currentSongIdx, playing: state.isPlaying, beat: state.pausedBeat,
        elapsed: state.anchor.time - anchor, cue: oldCue.gain.value, music: oldMusic.gain.value };
    });
    expect(result.index).toBe(1);
    expect(result.playing).toBe(mode !== 'stop');
    expect(result.beat).toBe(0);
    if (mode === 'overlap') {
      expect(result.elapsed).toBeCloseTo(2, 1);
      expect(result.cue).toBe(0);
      expect(result.music).toBeGreaterThan(0);
      expect(result.music).toBeLessThan(1);
    }
  });
}

test('transpose, mezcla, transporte y persistencia entre canciones', async ({ page }) => {
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  const result = await page.evaluate(async () => {
    const { state } = await import('/js/state/store.js');
    await window.selectTransposeKey('D');
    await window.play();
    const playing = state.isPlaying;
    const bpm = state.bpm;
    const rates = Object.values(state.REAL_STEM_SOURCES).map(source => source.playbackRate.value);
    const excluded = ['drums', 'click', 'guide'].every(id => window.isTransposeExcludedStem(id));
    const routes = state.REAL_STRETCH_ROUTES.length;
    window.toggleSectionLoopFor(0);
    const looping = state.isSectionLooping;
    state.STEMS.keys.muted = true; window.applyMix();
    await new Promise(resolve => setTimeout(resolve, 150));
    const muted = state.STEMS.keys.faderNode.gain.value < 0.01;
    window.pause(); const paused = !state.isPlaying;
    window.selectSong(1); window.selectSong(0);
    const retained = state.transposeTargetKey;
    window.stopAll();
    return { playing, bpm, rates, excluded, routes, looping, muted, paused, retained };
  });
  expect(result).toMatchObject({ playing: true, bpm: 120, excluded: true, looping: true, muted: true, paused: true, retained: 'D' });
  expect(result.routes).toBeGreaterThan(0);
  expect(result.rates.every(rate => rate === 1)).toBe(true);
  expect(errors).toEqual([]);
});

test('EQ procesa audio y conserva ajustes separados por canción', async ({ page }) => {
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  const button = page.locator('#mixer [data-stem="keys"][data-act="eq"]');
  await button.click();
  const panel = page.getByRole('dialog', { name: /^Ecualizador/ });
  const gain = panel.locator('[data-band="1"][data-key="gainDb"]');
  await gain.fill('12');
  await gain.press('Tab');
  await expect.poll(() => page.evaluate(async () => {
    const { readEq } = await import('/js/audio/eq.js');
    return readEq('keys').bands[1].gainDb;
  })).toBe(12);
  const ratio = await page.evaluate(async () => {
    const { state } = await import('/js/state/store.js');
    const { applyEq, readEq } = await import('/js/audio/eq.js');
    const settings = readEq('keys');
    const ctx = state.ctx;
    await ctx.resume();
    const tone = ctx.createOscillator();
    tone.frequency.value = 400;
    tone.connect(state.STEMS.keys.node);
    tone.start();
    const samples = new Float32Array(512);
    async function rms(bypass) {
      await applyEq('keys', { ...settings, bypass });
      await new Promise(resolve => setTimeout(resolve, 250));
      state.STEMS.keys.ana.getFloatTimeDomainData(samples);
      return Math.sqrt(samples.reduce((sum, value) => sum + value ** 2, 0) / samples.length);
    }
    try { return await rms(false) / await rms(true); }
    finally { tone.stop(); }
  });
  expect(ratio).toBeGreaterThan(3.5);
  await panel.getByRole('button', { name: 'Cerrar ecualizador' }).click();
  await page.evaluate(() => window.selectSong(1));
  await button.click();
  await expect(gain).toHaveValue('0');
});

test('Edición guarda la configuración de una canción y quita solo la fila confirmada', async ({ page }) => {
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  await page.evaluate(async () => {
    const { state } = await import('/js/state/store.js');
    const { readEq, saveEq } = await import('/js/audio/eq.js');
    state.STEMS.keys.gain = 0.5;
    const eq = readEq('keys');
    eq.bands[1].gainDb = 3;
    saveEq('keys', eq);
    state.transposeTargetKey = 'D';
  });
  const save = page.waitForRequest(req => req.url().endsWith('/api/setlists') && req.method() === 'POST');
  await page.locator('#btnSaveArranger').click();
  const [setlist] = (await save).postDataJSON();
  expect(setlist.songs[0]).toMatchObject({
    transposeKey: 'D', sections: [{ name: 'INTRO' }, { name: 'VERSO' }],
    mix: { keys: { gain: 0.5 } }
  });
  expect(setlist.songs[0].mix.keys.eq.bands[1].gainDb).toBe(3);
  expect(setlist.songs[0].mix.master.gain).toBeGreaterThan(0);
  const list = page.locator('#editionSongItemsList');
  page.once('dialog', dialog => dialog.dismiss());
  await list.getByRole('button', { name: 'Quitar canción de la setlist' }).first().click();
  await expect(list.locator('.song-card')).toHaveCount(2);
  page.once('dialog', dialog => dialog.accept());
  await list.getByRole('button', { name: 'Quitar canción de la setlist' }).first().click();
  await expect(list.locator('.song-card')).toHaveCount(1);
  await expect(list.locator('.song-card.active')).toContainText('Prueba 1');
});

test('Show selecciona en pausa y espera el final de la sección al reproducir', async ({ page }) => {
  await fixture(page);
  await page.locator('#btnViewShow').click();
  await expect(page.locator('#openUploadBtn')).toBeHidden();
  await page.evaluate(async () => {
    const { state } = await import('/js/state/store.js');
    state.SONG.sections[1].len = 1;
    state.SONG.sections.push({ name: 'PUENTE', bar: 3, len: 1 });
  });
  const bridge = page.getByRole('button', { name: 'PUENTE', exact: true });
  await bridge.click();
  await expect(page.locator('#moHeroSec')).toHaveText('PUENTE');
  await expect(page.locator('#moHeroTime')).not.toContainText('NaN');
  await page.evaluate(async () => {
    window.stopAll();
    await window.play({ fromBeginning: true });
  });
  await bridge.click();
  await expect(page.locator('#moHeroNextSec')).toContainText('EN COLA: PUENTE');
  await expect(page.locator('#moHeroSec')).toHaveText('INTRO');
  await expect(page.locator('#moHeroSec')).toHaveText('PUENTE', { timeout: 6500 });
  await expect(bridge).toHaveAttribute('aria-pressed', 'false');
});

test('diálogos, temas y controles HTML conservados', async ({ page }) => {
  const errors = []; page.on('pageerror', e => errors.push(e.message));
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  await page.locator('.sc-key-pill').first().click();
  await expect(page.locator('#moTransposePicker')).toHaveAttribute('aria-hidden', 'false');
  await page.locator('#moTransposeNoteGrid [data-note="D"]').click();
  await expect(page.locator('.sc-key-current').first()).toHaveText('D');
  await expect(page.locator('#moHeroKey')).toHaveText('D');
  await expect(page.locator('#moTransposeNoteGrid [data-note="E"]')).toHaveClass(/original/);
  await page.evaluate(() => { closeTransposePicker(); openMoPadPicker(); });
  await expect(page.locator('#moPadPicker')).toHaveAttribute('aria-hidden', 'false');
  await page.evaluate(() => { selectMoPadNote('A#'); closeMoPadPicker(); });
  const note = await page.evaluate(async () => (await import('/js/state/store.js')).state.currentPadKeyName);
  expect(note).toBe('A#');
  await page.evaluate(() => { startPad(10, 'A#'); });
  expect(await page.evaluate(async () => (await import('/js/state/store.js')).state.isContinuousPadPlaying)).toBe(true);
  await page.waitForFunction(async () => {
    const { state } = await import('/js/state/store.js');
    return state.padGain && state.padGain.gain.value === 1 && state.padOscs.length === 0;
  });
  await page.evaluate(() => stopPad());
  await page.locator('#btnViewShow').click();
  await page.evaluate(() => document.querySelector('#themeToggleRow').click());
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await page.screenshot({ path: 'test-results/light-landscape.png', fullPage: true, animations: 'disabled' });
  await page.evaluate(() => document.querySelector('#themeToggleRow').click());
  await expect(page.locator('html')).not.toHaveAttribute('data-theme', 'light');
  await page.screenshot({ path: 'test-results/dark-landscape.png', fullPage: true, animations: 'disabled' });
  expect(errors).toEqual([]);
});


test('niveles en dB, onda según ganancia y cuenta en Edición', async ({ page }) => {
  await page.setViewportSize({ width: 736, height: 663 });
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  await expect(page.locator('#btnSidebarAddSong')).toHaveText('+');
  await expect(page.locator('#sidebarAccountSlot #roleToggleBtn')).toBeVisible();
  await page.locator('#roleToggleBtn').click();
  await expect(page.locator('#userDropdown')).toBeVisible();
  await page.locator('#roleToggleBtn').click();
  const fader = page.locator('.fader[data-stem="keys"]');
  await fader.dblclick();
  await expect(fader).toHaveAttribute('aria-valuenow', '0.0');
  const height = () => page.evaluate(() => {
    const cv = document.querySelector('.tl-wave[data-stem="keys"]');
    const pixels = cv.getContext('2d').getImageData(0, 0, cv.width, cv.height).data;
    return pixels.reduce((sum, value, i) => sum + (i % 4 === 3 ? value : 0), 0);
  });
  const unity = await height();
  await fader.press('End');
  await expect(fader).toHaveAttribute('aria-valuenow', '10.0');
  expect(await height()).toBeGreaterThan(unity);
  const gain = await page.evaluate(async () => (await import('/js/state/store.js')).state.STEMS.keys.gain);
  expect(gain).toBeCloseTo(Math.sqrt(10), 5);
  await fader.press('Home');
  await expect(fader).toHaveAttribute('aria-valuenow', '-60.0');
  expect(await height()).toBeLessThan(unity);
  await page.locator('.fader[data-stem="master"]').dblclick();
  await page.screenshot({ path: 'test-results/edition-levels-dark.png' });
  await page.evaluate(() => document.documentElement.setAttribute('data-theme', 'light'));
  await page.screenshot({ path: 'test-results/edition-levels-light.png' });
  await page.locator('#btnViewShow').click();
  await expect(page.locator('#headerAccountSlot #roleToggleBtn')).toBeHidden();
  await expect(page.locator('#moMasterSlider')).toHaveValue('0');
});


test('menú sobre el timeline en móvil y línea continua sin audio', async ({ page }) => {
  await fixture(page);
  await page.locator('#btnViewEdition').click();
  for (const size of [{width: 736, height: 663}, {width: 932, height: 430}, {width: 390, height: 663}]) {
    await page.setViewportSize(size);
    await page.locator('#roleToggleBtn').click();
    const menu = page.locator('body > #userDropdown');
    await expect(menu).toBeVisible();
    const bounds = await menu.boundingBox();
    await page.screenshot({ path: `test-results/account-menu-${size.width}.png` });
    expect(bounds.x).toBeGreaterThanOrEqual(0);
    expect(bounds.y).toBeGreaterThanOrEqual(0);
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(size.width);
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(size.height);
    expect(await menu.evaluate(el => {
      const r = el.getBoundingClientRect();
      return el.contains(document.elementFromPoint(r.right - 5, r.top + 20));
    })).toBe(true);
    await page.keyboard.press('Escape');
    await expect(menu).not.toBeVisible();
  }
  await page.setViewportSize({width: 736, height: 663});
  const continuous = await page.evaluate(async () => {
    const {state} = await import('/js/state/store.js');
    state.REAL_STEM_BUFFERS.keys = window.getAudioCtx().createBuffer(1, 44100, 44100);
    window.drawWave('keys');
    const cv = document.querySelector('.tl-wave[data-stem="keys"]');
    const row = cv.getContext('2d').getImageData(0, Math.floor(cv.height / 2), cv.width, 1).data;
    return Array.from({length: cv.width}, (_, i) => row[i * 4 + 3]).every(alpha => alpha > 0);
  });
  expect(continuous).toBe(true);
});

