const {execFileSync} = require('child_process'), fs = require('fs'), os = require('os'), path = require('path');
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
const FAKE_ANON = b64({alg:'HS256', typ:'JWT'}) + '.' + b64({role:'anon', iss:'supabase'}) + '.signaturesignaturesignature';
function build(env) {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'sp-'));
  const e = Object.assign({}, process.env, {SP_OUT_DIR: out}, env);
  execFileSync(require('../scripts/python')(), [path.join(__dirname, '../scripts/build-course.py')], {env: e, stdio: 'pipe'});
  return path.join(out, 'index.html');
}
module.exports = {build, FAKE_ANON, URL: 'https://testproj.supabase.co'};
