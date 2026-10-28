// Picks a Python interpreter that works on Windows, macOS and Linux.
// Override with the PYTHON environment variable (e.g. PYTHON=py).
module.exports = function pythonCommand() {
  if (process.env.PYTHON) return process.env.PYTHON;
  return process.platform === 'win32' ? 'python' : 'python3';
};
