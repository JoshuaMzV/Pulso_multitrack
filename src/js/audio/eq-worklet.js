/* global AudioWorkletProcessor, registerProcessor, sampleRate */
class PulsoEqProcessor extends AudioWorkletProcessor {
  constructor({ processorOptions }) {
    super();
    this.dsp = new WebAssembly.Instance(processorOptions.module).exports;
    this.dsp._initialize?.();
    this.dsp.eq_init(sampleRate);
    this.left = new Float32Array(this.dsp.memory.buffer, this.dsp.eq_left(), 128);
    this.right = new Float32Array(this.dsp.memory.buffer, this.dsp.eq_right(), 128);
    this.port.onmessage = ({ data }) => {
      data.bands.forEach(({ shape, frequency, gainDb, q }, index) => {
        this.dsp.eq_band(index, shape, frequency, gainDb, q);
      });
      this.dsp.eq_output(data.outputDb, Number(data.bypass));
    };
  }

  process([input], [output]) {
    if (!input?.length) return true;
    const [outLeft, outRight] = output;
    const [inLeft, inRight = inLeft] = input;
    for (let offset = 0; offset < outLeft.length; offset += 128) {
      const frames = Math.min(128, outLeft.length - offset);
      for (let frame = 0; frame < frames; frame++) {
        this.left[frame] = inLeft[offset + frame];
        this.right[frame] = inRight[offset + frame];
      }
      this.dsp.eq_process(frames);
      for (let frame = 0; frame < frames; frame++) {
        outLeft[offset + frame] = this.left[frame];
        if (outRight) outRight[offset + frame] = this.right[frame];
      }
    }
    return true;
  }
}

registerProcessor('pulso-eq', PulsoEqProcessor);
