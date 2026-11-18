// Conservative first-install fit check. The scheduler and Helm readiness remain authoritative.
import { readFileSync } from 'node:fs';
const [nodes, pods, rendered] = process.argv.slice(2).map(path => JSON.parse(readFileSync(path, 'utf8')));
const units = { '': 1, n: 1e-9, u: 1e-6, m: 1e-3, k: 1e3, K: 1e3, M: 1e6, G: 1e9,
  T: 1e12, P: 1e15, E: 1e18, Ki: 1024, Mi: 1024 ** 2, Gi: 1024 ** 3, Ti: 1024 ** 4 };
function quantity(value = '0') {
  const match = String(value).match(/^(\d+(?:\.\d+)?)([a-zA-Z]*)$/);
  if (!match || units[match[2]] === undefined) throw new Error('Unsupported resource quantity');
  return Number(match[1]) * units[match[2]];
}
function requests(spec) {
  return ['cpu', 'memory'].map(resource => {
    const get = container => quantity(container.resources?.requests?.[resource] ?? container.resources?.limits?.[resource]);
    const regular = (spec.containers ?? []).reduce((sum, container) => sum + get(container), 0);
    let sidecars = 0;
    let peak = 0;
    for (const init of spec.initContainers ?? []) {
      if (init.restartPolicy === 'Always') sidecars += get(init);
      peak = Math.max(peak, sidecars + (init.restartPolicy === 'Always' ? 0 : get(init)));
    }
    return Math.max(regular + sidecars, peak, quantity(spec.resources?.requests?.[resource])) + quantity(spec.overhead?.[resource]);
  }).concat(1);
}
const available = nodes.items.filter(node => !node.spec?.unschedulable &&
  !node.spec?.taints?.some(taint => ['NoSchedule', 'NoExecute'].includes(taint.effect)) &&
  node.status.conditions.some(condition => condition.type === 'Ready' && condition.status === 'True'))
  .map(node => ({ name: node.metadata.name, free: ['cpu', 'memory', 'pods'].map(key => quantity(node.status.allocatable[key])) }));
// With CAPACITY_NAMESPACE set, running pods of the rendered workloads in that
// namespace are the ones an upgrade replaces: count them once, as demand, not
// also as used capacity.
const releaseNamespace = process.env.CAPACITY_NAMESPACE;
const selectors = rendered.filter(resource => ['Deployment', 'StatefulSet'].includes(resource.kind))
  .map(resource => Object.entries(resource.spec.selector?.matchLabels ?? {})).filter(selector => selector.length > 0);
const replacedByRelease = pod => releaseNamespace !== undefined && pod.metadata?.namespace === releaseNamespace &&
  selectors.some(selector => selector.every(([key, value]) => pod.metadata?.labels?.[key] === value));
for (const pod of pods.items) {
  if (['Succeeded', 'Failed'].includes(pod.status.phase) || replacedByRelease(pod)) continue;
  const node = available.find(node => node.name === pod.spec.nodeName);
  if (node) node.free = node.free.map((value, index) => value - requests(pod.spec)[index]);
}
const pending = pods.items.filter(pod => !pod.spec.nodeName && pod.status.phase === 'Pending' && !replacedByRelease(pod) &&
  pod.spec.nodeSelector?.['node.cluster.x-k8s.io/pool'] === 'general').map(pod => requests(pod.spec));
const demand = [...pending, [0.025, 32 * 1024 ** 2, 1]]; // one disposable readiness pod
// Replicas that require distinct hosts (hostname anti-affinity on their own
// labels) share a spread group: no two of them may land on one node.
function spreadGroup(resource) {
  const labels = resource.spec.template.metadata?.labels ?? {};
  const terms = resource.spec.template.spec.affinity?.podAntiAffinity?.requiredDuringSchedulingIgnoredDuringExecution ?? [];
  const own = terms.find(term => term.topologyKey === 'kubernetes.io/hostname' &&
    Object.entries(term.labelSelector?.matchLabels ?? {}).every(([key, value]) => labels[key] === value));
  return own ? `${resource.kind}/${resource.metadata.name}` : undefined;
}
for (const resource of rendered) {
  if (['Deployment', 'StatefulSet'].includes(resource.kind)) {
    const group = spreadGroup(resource);
    for (let i = 0; i < (resource.spec.replicas ?? 1); i++) demand.push(Object.assign(requests(resource.spec.template.spec), { group }));
  } else if (resource.kind === 'Cluster' && resource.apiVersion === 'postgresql.cnpg.io/v1') {
    for (let i = 0; i < resource.spec.instances; i++) demand.push(requests({ containers: [{ resources: resource.spec.resources }] }));
  }
}
demand.sort((a, b) => b[0] - a[0] || b[1] - a[1]);
const fits = (free, needed) => free.every((value, index) => value + 1e-8 >= needed[index]);
// Reserve a whole server surge slot on one general node; do not consume it for this pilot.
const reserve = [1, 1024 ** 3, 1];
function qualifies(nodes) {
  for (const candidate of nodes) {
    if (!fits(candidate.free, reserve)) continue;
    const placement = nodes.map(node => ({ free: node.free.map((value, index) => value - (node === candidate ? reserve[index] : 0)), groups: new Set() }));
    const placed = demand.every(needed => {
      const target = placement.filter(node => fits(node.free, needed) && !(needed.group && node.groups.has(needed.group)))
        .sort((a, b) => a.free[0] - b.free[0] || a.free[1] - b.free[1])[0];
      if (!target) return false;
      needed.forEach((value, index) => { target.free[index] -= value; });
      if (needed.group) target.groups.add(needed.group);
      return true;
    });
    if (placed) return true;
  }
  return false;
}
// With CAPACITY_TOLERATE_NODE_LOSS=1 the plan must also fit after losing any
// one ready node, so a node failure cannot leave quorum members unschedulable.
const tolerateNodeLoss = process.env.CAPACITY_TOLERATE_NODE_LOSS === '1';
const scenarios = [available, ...(tolerateNodeLoss ? available.map(lost => available.filter(node => node !== lost)) : [])];
if (!scenarios.every(qualifies)) {
  console.error('FAIL: insufficient schedulable general-pool CPU, memory, pod slots or distinct hosts while retaining server surge headroom' +
    (tolerateNodeLoss ? ' and a one-node failure reserve' : ''));
  process.exitCode = 1;
} else {
  console.log(`PASS: ${demand.length} planned/pending pods fit across ${available.length} ready general nodes, retaining 1 CPU/1 GiB/server pod slot` +
    (tolerateNodeLoss ? ' after losing any one node' : ''));
}
