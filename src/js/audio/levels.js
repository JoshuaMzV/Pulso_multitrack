// Escala compartida: la ganancia del motor permanece lineal; los controles usan dB.
export const MIN_DB = -60;
export const MAX_DB = 10;
export const gainToDb = gain => gain > 0 ? Math.max(MIN_DB, Math.min(MAX_DB, 20 * Math.log10(gain))) : MIN_DB;
export const dbToGain = db => 10 ** (Math.max(MIN_DB, Math.min(MAX_DB, db)) / 20);
export const gainToPosition = gain => (gainToDb(gain) - MIN_DB) / (MAX_DB - MIN_DB);
export const positionToGain = position => dbToGain(MIN_DB + Math.max(0, Math.min(1, position)) * (MAX_DB - MIN_DB));
export const formatGain = gain => gain <= 0 ? '−∞ dB' : `${gainToDb(gain) > 0 ? '+' : ''}${gainToDb(gain).toFixed(1)} dB`;
