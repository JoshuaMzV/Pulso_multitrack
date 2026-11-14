// Dependencias locales para Pinegrow, servidor de desarrollo y Capacitor.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const vendor = path.join(root, 'src/vendor');
function copy(source, target) {
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(source, target);
}
function prepareVendor() {
  const packages = [
    ['lucide/dist/umd/lucide.min.js', 'lucide.min.js'],
    ['lucide/LICENSE', 'lucide.LICENSE'],
    ['jszip/dist/jszip.min.js', 'jszip.min.js'],
    ['jszip/LICENSE.markdown', 'jszip.LICENSE.md'],
  ];
  for (const [source, target] of packages) copy(path.join(root, 'node_modules', source), path.join(vendor, target));
  let css = '';
  for (const [name, weights] of [['inter', [400,500,600,700,800,900]], ['jetbrains-mono', [400,500,600,700]]]) {
    const folder = path.join(root, 'node_modules/@fontsource', name);
    copy(path.join(folder, 'LICENSE'), path.join(vendor, `${name}.LICENSE`));
    for (const weight of weights) {
      const source = fs.readFileSync(path.join(folder, `latin-${weight}.css`), 'utf8');
      for (const match of source.matchAll(/url\(\.\/files\/([^)]*)\)/g)) copy(path.join(folder, 'files', match[1]), path.join(vendor, 'fonts', match[1]));
      css += source.replaceAll('./files/', './fonts/') + '\n';
    }
  }
  fs.writeFileSync(path.join(vendor, 'fonts.css'), css);
}
if (require.main === module) prepareVendor();
module.exports = { prepareVendor };
