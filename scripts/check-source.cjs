const fs = require('node:fs');
const path = require('node:path');
const acorn = require('acorn');
const scope = require('eslint-scope');
const root = path.resolve(__dirname, '../src');
const allowed = new Set('TextEncoder crypto AudioWorkletProcessor registerProcessor sampleRate WebAssembly URL AbortSignal Array Boolean Date Error FileReader FormData JSON JSZip Map WeakMap Float32Array Math Number Object Promise Set String Uint8Array addEventListener alert clearInterval clearTimeout confirm console document encodeURIComponent fetch indexedDB localStorage location lucide navigator parseFloat parseInt performance prompt removeEventListener requestAnimationFrame setInterval setTimeout undefined window'.split(' '));
let count = 0;
for (const file of fs.readdirSync(path.join(root, 'js'), { recursive: true }).filter(f => f.endsWith('.js'))) {
  const full = path.join(root, 'js', file);
  const tree = acorn.parse(fs.readFileSync(full, 'utf8'), { ecmaVersion: 2022, sourceType: 'module', ranges: true });
  for (const reference of scope.analyze(tree, { ecmaVersion: 2022, sourceType: 'module' }).globalScope.through) {
    if (!allowed.has(reference.identifier.name)) throw new Error(`${file}: referencia sin importar: ${reference.identifier.name}`);
  }
  for (const node of tree.body.filter(n => n.type === 'ImportDeclaration')) {
    if (!fs.existsSync(path.resolve(path.dirname(full), node.source.value))) throw new Error(`${file}: import ausente ${node.source.value}`);
  }
  count++;
}
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
if (/<script\s+src=["']https?:/.test(html) || /fonts.googleapis.com/.test(html)) throw new Error('Dependencia de CDN en HTML');
console.log(`${count} módulos: sintaxis, imports y referencias correctas.`);


