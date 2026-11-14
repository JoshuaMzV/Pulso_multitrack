// Publicación temporal explícita; el servidor local se inicia por separado.
const { spawn } = require('node:child_process');
const child = spawn('cloudflared', ['tunnel', '--url', 'http://127.0.0.1:5000'], { stdio: 'inherit' });
child.on('error', error => { console.error(error.message); process.exitCode = 1; });
child.on('exit', code => { process.exitCode = code ?? 1; });
