const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');

// SwiftPM's forced resolve can keep an older registry download in workspace
// state even after Package.resolved changes. Forget only those records so it
// restores the committed versions; retain sources, artifacts and other state.
function reconcileWorkspace(scratch) {
  const statePath = path.join(scratch, 'workspace-state.json');
  let contents;
  try {
    contents = fs.readFileSync(statePath, 'utf8');
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
  const state = JSON.parse(contents);
  const resolved = JSON.parse(fs.readFileSync(path.join(scratch, '..', 'Package.resolved'), 'utf8'));
  // The legacy lockfile predates registry dependencies.
  if (resolved.version === 1 && Array.isArray(resolved.object?.pins)) return [];
  if (!Array.isArray(state.object?.dependencies) || !Array.isArray(resolved.pins)) {
    throw new Error('Unrecognized SwiftPM workspace or lockfile format.');
  }
  const pins = new Map(resolved.pins.map(pin => [pin.identity.toLowerCase(), pin]));
  const removed = [];
  state.object.dependencies = state.object.dependencies.filter(dependency => {
    if (dependency.state?.name !== 'registryDownload') return true;
    const identity = dependency.packageRef.identity;
    const pin = pins.get(identity.toLowerCase());
    if (pin?.kind !== 'registry' || typeof pin.state?.version !== 'string'
        || dependency.state.version === pin.state.version) return true;
    removed.push(`${identity}: ${dependency.state.version} -> ${pin.state.version}`);
    return false;
  });
  if (removed.length === 0) return removed;

  const temporary = `${statePath}.${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, { flag: 'wx' });
    fs.renameSync(temporary, statePath);
  } finally {
    fs.rmSync(temporary, { force: true });
  }
  return removed;
}

module.exports = { reconcileWorkspace };
