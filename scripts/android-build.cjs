const { spawnSync } = require('node:child_process');
const path = require('node:path');
const windows = process.platform === 'win32';
const result = spawnSync(windows ? 'cmd.exe' : './gradlew', windows ? ['/d', '/c', 'gradlew.bat assembleDebug'] : ['assembleDebug'], {
  cwd: path.resolve(__dirname, '../android'), stdio: 'inherit'
});
if (result.error) console.error(result.error.message);
process.exitCode = result.status ?? 1;
