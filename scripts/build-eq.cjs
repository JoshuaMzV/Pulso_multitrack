const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const exportsList = ['init', 'left', 'right', 'band', 'output', 'process']
  .map(name => '_eq_' + name).join(',');
const args = [
  'dsp/eq_wasm.cpp', '-std=c++17', '-O3', '--no-entry',
  '-sSTANDALONE_WASM=1', '-sEXPORTED_FUNCTIONS=' + exportsList,
  '-o', 'src/assets/pulso-eq.wasm'
];
const windows = process.platform === 'win32';
const result = windows
  ? spawnSync('cmd.exe', ['/d', '/c', 'em++.bat ' + args.join(' ')], { cwd: root, stdio: 'inherit' })
  : spawnSync('em++', args, { cwd: root, stdio: 'inherit' });
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;
