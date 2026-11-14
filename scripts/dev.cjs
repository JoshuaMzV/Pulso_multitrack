const { spawn } = require('node:child_process');
const path = require('node:path');
const fs = require('node:fs');
const { prepareVendor } = require('./prepare-vendor.cjs');
prepareVendor();
const root = path.resolve(__dirname, '..');
const localPython = path.join(root, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
const python = process.env.PULSO_PYTHON || (fs.existsSync(localPython) ? localPython : 'python');
const child = spawn(python, ['-X', 'utf8', '-m', 'backend.local_server'], { cwd: root, stdio: 'inherit',
  env: { ...process.env, PULSO_WEB_DIR: path.join(root, 'src') } });
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', code => { process.exitCode = code ?? 1; });
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => child.kill(signal));
