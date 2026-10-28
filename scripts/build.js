// Cross-platform build entry point used by `npm run build` and `npm run build:lms`.
//   node scripts/build.js --local   practice-only build (no login/sync), base course
//   node scripts/build.js --lms     classroom build (needs SUPABASE_URL + SUPABASE_ANON_KEY)
const { spawnSync } = require('child_process');
const path = require('path');
const pythonCommand = require('./python');

const lms = process.argv.includes('--lms');
const env = Object.assign({}, process.env);
if (!lms) env.ALLOW_LOCAL_MODE = '1';
const script = lms ? 'build-course-lms.py' : 'build-course.py';
const r = spawnSync(pythonCommand(), [path.join(__dirname, script)], { stdio: 'inherit', env });
if (r.error) {
  console.error('Could not start Python (' + pythonCommand() + '): ' + r.error.message +
    '\nInstall Python 3 or set the PYTHON environment variable, e.g. $env:PYTHON="py"');
  process.exit(1);
}
process.exit(r.status === null ? 1 : r.status);
