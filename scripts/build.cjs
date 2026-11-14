const fs = require('node:fs');
const path = require('node:path');
const { prepareVendor } = require('./prepare-vendor.cjs');
const root = path.resolve(__dirname, '..');
const output = path.join(root, 'www');
if (path.resolve(output) !== path.resolve(root, 'www') ||
    (fs.existsSync(output) && fs.lstatSync(output).isSymbolicLink())) throw new Error('Destino de build inseguro');
if (fs.existsSync(path.join(output, 'songs'))) throw new Error('www/songs contiene datos: migrar y verificar antes de generar www.');
prepareVendor();
// Ruta constante dentro del proyecto; nunca se acepta un destino externo.
fs.rmSync(output, { recursive: true, force: true });
fs.mkdirSync(output, { recursive: true });
for (const entry of ['index.html', 'styles', 'js', 'assets', 'vendor']) {
  fs.cpSync(path.join(root, 'src', entry), path.join(output, entry), { recursive: true,
    filter: p => !/\.(bak|map)$/.test(p) });
}
console.log('Web generada en www/ (sin canciones ni datos de usuario).');
