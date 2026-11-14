import { getAudioCtx } from '../audio/engine.js';
import { applyEq, defaultEq, readEq, saveEq } from '../audio/eq.js';

export function openEq(id, label) {
  const ctx = getAudioCtx();
  const panel = document.createElement('dialog');
  panel.className = 'eq-panel';
  panel.setAttribute('aria-label', 'Ecualizador de ' + label);
  panel.innerHTML = `<form method="dialog"><strong data-title></strong>
    <button aria-label="Cerrar ecualizador">×</button></form>
    <p>Arrastra una banda · horizontal: frecuencia · vertical: ganancia</p>
    <div class="eq-graph"><canvas width="560" height="200" role="img" aria-label="Curva de respuesta"></canvas></div>
    <div data-fields></div><button type="button" data-reset>Restablecer</button>
    <p role="status"></p>`;
  panel.querySelector('[data-title]').textContent = 'EQ · ' + label;
  const fields = panel.querySelector('[data-fields]');
  const status = panel.querySelector('[role=status]');
  const canvas = panel.querySelector('canvas');
  const graph = canvas.getContext('2d');
  const graphBox = canvas.parentElement;
  const maxFrequency = Math.min(20000, ctx.sampleRate * .49);
  const frequencySpan = Math.log(maxFrequency / 20);
  const bandPosition = frequency => Math.max(0, Math.min(1, Math.log(frequency / 20) / frequencySpan));
  const frequencies = Float32Array.from({ length: canvas.width },
    (_, i) => 20 * Math.exp(frequencySpan * i / (canvas.width - 1)));
  const magnitude = new Float32Array(canvas.width);
  const phase = new Float32Array(canvas.width);
  const filters = defaultEq(id).bands.map(() => ctx.createBiquadFilter());
  let settings = readEq(id);
  let revision = 0;
  const handles = settings.bands.map((_, index) => {
    const handle = document.createElement('button');
    handle.type = 'button';
    handle.className = 'eq-handle';
    handle.textContent = index + 1;
    graphBox.append(handle);
    let drag;
    handle.addEventListener('pointerdown', event => {
      if (event.button !== 0 || drag) return;
      const { frequency, gainDb } = settings.bands[index];
      drag = { id: event.pointerId, x: event.clientX, y: event.clientY, frequency, gainDb };
      handle.setPointerCapture(event.pointerId);
    });
    handle.addEventListener('pointermove', event => {
      if (drag?.id !== event.pointerId) return;
      const bounds = canvas.getBoundingClientRect();
      const frequency = Math.round(20 * Math.exp(frequencySpan * Math.max(0, Math.min(1,
        bandPosition(drag.frequency) + (event.clientX - drag.x) / bounds.width))));
      const gainDb = Math.max(-12, Math.min(12,
        Math.round((drag.gainDb - (event.clientY - drag.y) * 32 / bounds.height) * 2) / 2));
      setBand(index, { frequency, gainDb });
      for (const key of ['frequency', 'gainDb']) {
        fields.querySelector(`[data-band="${index}"][data-key="${key}"]`).value = settings.bands[index][key];
      }
      update(false);
    });
    handle.addEventListener('lostpointercapture', () => {
      drag = null;
      update();
    });
    handle.addEventListener('click', event => {
      if (!event.detail) fields.querySelector(`[data-band="${index}"][data-key="frequency"]`).focus();
    });
    return handle;
  });

  function setBand(index, values) {
    settings = { ...settings, bands: settings.bands.map((band, i) =>
      i === index ? { ...band, ...values } : band) };
  }

  function draw() {
    const response = new Float32Array(canvas.width).fill(settings.bypass ? 0 : settings.outputDb);
    if (!settings.bypass) settings.bands.forEach((band, index) => {
      const filter = filters[index];
      filter.type = ['lowshelf', 'peaking', 'highshelf'][band.shape];
      filter.frequency.value = band.frequency;
      filter.gain.value = band.gainDb;
      filter.Q.value = band.q;
      filter.getFrequencyResponse(frequencies, magnitude, phase);
      for (let i = 0; i < response.length; i++) response[i] += 20 * Math.log10(magnitude[i]);
    });
    graph.clearRect(0, 0, canvas.width, canvas.height);
    graph.strokeStyle = '#8390a0';
    graph.beginPath();
    graph.moveTo(0, canvas.height / 2);
    graph.lineTo(canvas.width, canvas.height / 2);
    graph.stroke();
    graph.strokeStyle = document.documentElement.dataset.theme === 'light' ? '#4B6227' : '#dc862a';
    graph.beginPath();
    response.forEach((db, i) => graph.lineTo(i, canvas.height * Math.max(0, Math.min(1, .5 - db / 32))));
    graph.stroke();
    handles.forEach((handle, index) => {
      const { frequency, gainDb } = settings.bands[index];
      handle.style.left = `${100 * bandPosition(frequency)}%`;
      handle.style.top = `${100 * (.5 - gainDb / 32)}%`;
      handle.setAttribute('aria-label', `Banda ${index + 1}: ${frequency} Hz, ${gainDb} dB. Editar frecuencia`);
    });
  }

  async function update(persist = true) {
    const current = ++revision;
    draw();
    try {
      if (persist) saveEq(id, settings);
      await applyEq(id, settings);
      if (current === revision) {
        status.textContent = id === 'master' ? 'Click y talkback conservan su salida directa.' : '';
      }
    } catch (_) {
      if (current === revision) status.textContent = 'EQ no disponible. La reproducción conserva su ruta directa.';
    }
  }

  function render() {
    fields.innerHTML = settings.bands.map((band, i) => `<fieldset><legend>Banda ${i + 1}</legend>
      <label>Hz <input type="number" min="20" max="20000" step="1" value="${band.frequency}" data-band="${i}" data-key="frequency"></label>
      <label>dB <input type="number" min="-12" max="12" step="0.5" value="${band.gainDb}" data-band="${i}" data-key="gainDb"></label>
      ${band.shape === 1 ? `<label>Q <input type="number" min="0.1" max="12" step="0.1" value="${band.q}" data-band="${i}" data-key="q"></label>` : ''}
      </fieldset>`).join('') + `<label>Salida (dB) <input type="number" min="-12" max="12" step="0.5" data-key="outputDb" value="${settings.outputDb}"></label>
      <label><input type="checkbox" data-key="bypass" ${settings.bypass ? 'checked' : ''}> Bypass</label>`;
    draw();
  }

  fields.addEventListener('change', ({ target }) => {
    const { key, band } = target.dataset;
    if (!key || !target.checkValidity() || (key !== 'bypass' && !Number.isFinite(target.valueAsNumber))) return;
    const value = key === 'bypass' ? target.checked : target.valueAsNumber;
    if (band === undefined) settings = { ...settings, [key]: value };
    else setBand(Number(band), { [key]: value });
    update();
  });
  panel.querySelector('[data-reset]').onclick = () => {
    settings = defaultEq(id);
    render();
    update();
  };
  panel.addEventListener('close', () => panel.remove());
  document.body.append(panel);
  render();
  panel.showModal();
}
