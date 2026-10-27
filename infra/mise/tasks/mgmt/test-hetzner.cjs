const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const spec = JSON.parse(execFileSync('yq', ['-o=json', '.', path.join(root, 'infra/k8s/mgmt/talos/hetzner.yaml')]));

// The full reconciler runs against a stateful fake Cloud API. No token or
// network is available, and any unexpected command fails the test.
const fakeCloud = `#!/usr/bin/env node
const fs = require('node:fs');
const dir = process.env.MGMT_TEST_DIR;
const state = JSON.parse(fs.readFileSync(dir + '/state.json'));
const args = process.argv.slice(2);
const [resource, action, name] = args;
const flag = key => args[args.indexOf(key) + 1];
const out = value => console.log(JSON.stringify(value));
const servers = state.spec.nodes.map((n, i) => ({
  id: i + 1, name: n.name, location: {name: n.location || state.spec.location},
  protection: {delete: true, rebuild: true}, private_net: [{network: 100, ip: n.privateIP}]
}));
fs.appendFileSync(dir + '/calls.jsonl', JSON.stringify(args) + '\\n');
switch (resource + ' ' + action) {
  case 'location describe': out({network_zone: 'eu-central'}); break;
  case 'network list': out([{id:100, name:state.spec.network.name, ip_range:state.spec.network.ipRange,
    subnets:[{ip_range:state.spec.network.subnet}], protection:{delete:true}}]); break;
  case 'placement-group list': out([{name:state.spec.server.placementGroup, type:'spread'}]); break;
  case 'image list': out([{id:1, description:state.spec.server.image}]); break;
  case 'firewall describe': out({}); break;
  case 'server list': out(servers); break;
  case 'server describe': out(servers.find(s => s.name === name)); break;
  case 'primary-ip list': out([{name:state.spec.loadBalancer.name, type:'ipv4', ip:'192.0.2.1', protection:{delete:true}}]); break;
  case 'load-balancer list':
  case 'load-balancer describe':
    state.reads++;
    if (state.scenario === 'health-lost' && state.reads > 1) {
      state.targets.forEach(t => { if (t.server.id !== 1) t.health_status = []; });
    }
    if (state.pending && ++state.polls >= 2) {
      const target = state.targets.find(t => t.server.id === state.pending);
      target.health_status = [{listen_port:6443, status:'healthy'}];
      state.pending = null;
    }
    const lb = {name:state.spec.loadBalancer.name, location:{name:state.spec.location},
      public_net:{ipv4:{ip:'192.0.2.1'}}, load_balancer_type:{name:state.spec.loadBalancer.type},
      protection:{delete:true}, private_net:[{network:100}],
      services:[{listen_port:6443, destination_port:6443, protocol:'tcp'}], targets:state.targets};
    out(action === 'list' ? [lb] : lb); break;
  case 'load-balancer remove-target': {
    if (state.pending) throw Error('removed another target before observing recovery');
    const server = servers.find(s => s.name === flag('--server'));
    state.targets = state.targets.filter(t => t.server.id !== server.id);
    break;
  }
  case 'load-balancer add-target': {
    const server = servers.find(s => s.name === flag('--server'));
    state.targets.push({type:'server', server:{id:server.id}, use_private_ip:state.spec.loadBalancer.usePrivateIP, health_status:[]});
    state.pending = server.id; state.polls = 0; break;
  }
  default: throw Error('unexpected cloud operation: ' + args.join(' '));
}
fs.writeFileSync(dir + '/state.json', JSON.stringify(state));
`;

function reconcile(scenario, apply) {
  fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
  const dir = fs.mkdtempSync(path.join(root, 'tmp/mgmt-hetzner-test-'));
  try {
    fs.writeFileSync(path.join(dir, 'hcloud'), fakeCloud, { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'sleep'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify({
      spec, scenario, reads: 0,
      targets: spec.nodes.map((_, i) => ({
        type: 'server', server: { id: i + 1 }, use_private_ip: !spec.loadBalancer.usePrivateIP,
        health_status: [{ listen_port: 6443, status: 'healthy' }],
      })),
    }));
    const result = spawnSync('bash', [path.join(__dirname, 'reconcile-hetzner.sh'), ...(apply ? ['--apply'] : [])], {
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, HCLOUD_TOKEN: 'offline-test', MGMT_TEST_DIR: dir },
      encoding: 'utf8', timeout: 15000,
    });
    const calls = fs.readFileSync(path.join(dir, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
    return { result, calls, state: JSON.parse(fs.readFileSync(path.join(dir, 'state.json'))) };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('target switches observe recovery before the next removal', () => {
  const { result, calls, state } = reconcile('healthy', true);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(calls.filter(c => c[1] === 'remove-target').length, spec.nodes.length);
  assert.equal(calls.filter(c => c[1] === 'add-target').length, spec.nodes.length);
  assert.ok(state.targets.every(t => t.use_private_ip === spec.loadBalancer.usePrivateIP));
  assert.equal(state.pending, null);
});

test('fresh sibling health loss aborts before any target mutation', () => {
  const { result, calls } = reconcile('health-lost', true);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /no other server target is healthy/);
  assert.equal(calls.filter(c => ['remove-target', 'add-target'].includes(c[1])).length, 0);
});

test('planning prints switches but makes no cloud mutations', () => {
  const { result, calls } = reconcile('healthy', false);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /would wait for target/);
  assert.equal(calls.filter(c => ['remove-target', 'add-target'].includes(c[1])).length, 0);
});
