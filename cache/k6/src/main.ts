import { Options } from 'k6/options';
import { MIXED_RATES, KV_SAT_RATES, REGION, COMMIT_SHA } from './config.ts';
import { ALL_NAMES } from './metrics.ts';
import { payloads } from './payloads.ts';
import { authenticate } from './lib/auth.ts';
import { seedAll } from './lib/seed.ts';
import { SetupData } from './types.ts';

// --- Init context: load fixture payloads ---
payloads['10kb'] = open('../fixtures/10kb.bin', 'b');
payloads['256kb'] = open('../fixtures/256kb.bin', 'b');
payloads['2mb'] = open('../fixtures/2mb.bin', 'b');
payloads['10mb'] = open('../fixtures/10mb.bin', 'b');
payloads['25mb'] = open('../fixtures/25mb.bin', 'b');
payloads['50mb'] = open('../fixtures/50mb.bin', 'b');

// --- Re-export scenario functions so k6 can call them by name ---
export { xcodeReadHit, xcodeWrite } from './scenarios/xcode.ts';
export { moduleExists, moduleReadHit, moduleWrite } from './scenarios/module.ts';
export { gradleReadHit, gradleWrite } from './scenarios/gradle.ts';
export { kvGet, kvPut, kvSatGet, kvSatPut } from './scenarios/kv.ts';

// --- Scenario builder ---
interface ScenarioConfig {
  exec: string;
  rate: number;
  startTime?: string;
  preAllocatedVUs?: number;
  maxVUs?: number;
}

function makeScenario(cfg: ScenarioConfig): any {
  var halfRate = Math.ceil(cfg.rate * 0.5);
  var fullRate = cfg.rate;
  var burstRate = Math.ceil(cfg.rate * 1.5);

  return {
    executor: 'ramping-arrival-rate',
    exec: cfg.exec,
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: cfg.preAllocatedVUs || Math.max(Math.ceil(burstRate * 0.15), 10),
    maxVUs: cfg.maxVUs || Math.max(Math.ceil(burstRate * 0.5), 20),
    startTime: cfg.startTime || '0s',
    stages: [
      { duration: '1m', target: halfRate },
      { duration: '1m', target: halfRate },
      { duration: '30s', target: fullRate },
      { duration: '9m30s', target: fullRate },
      { duration: '30s', target: burstRate },
      { duration: '1m30s', target: burstRate },
    ],
  };
}

// --- Build k6 options ---
var scenarios: Record<string, any> = {};

// Mixed phase scenarios (start at 0s, run for 14m)
var mixedEntries = [
  { key: 'kv_get', exec: 'kvGet' },
  { key: 'kv_put', exec: 'kvPut' },
  { key: 'xcode_read_hit', exec: 'xcodeReadHit' },
  { key: 'xcode_write', exec: 'xcodeWrite' },
  { key: 'module_exists', exec: 'moduleExists' },
  { key: 'module_read_hit', exec: 'moduleReadHit' },
  { key: 'module_write', exec: 'moduleWrite' },
  { key: 'gradle_read_hit', exec: 'gradleReadHit' },
  { key: 'gradle_write', exec: 'gradleWrite' },
];

for (var i = 0; i < mixedEntries.length; i++) {
  var entry = mixedEntries[i];
  var rate = MIXED_RATES[entry.key];
  if (rate) {
    scenarios[entry.key] = makeScenario({ exec: entry.exec, rate: rate });
  }
}

// KV saturation phase (starts after mixed at 14m)
var kvEntries = [
  { key: 'kv_sat_get', exec: 'kvSatGet' },
  { key: 'kv_sat_put', exec: 'kvSatPut' },
];

for (var ki = 0; ki < kvEntries.length; ki++) {
  var kvEntry = kvEntries[ki];
  var kvRate = KV_SAT_RATES[kvEntry.key];
  if (kvRate) {
    scenarios[kvEntry.key] = makeScenario({
      exec: kvEntry.exec,
      rate: kvRate,
      startTime: '14m',
      preAllocatedVUs: Math.max(Math.ceil(kvRate * 1.5 * 0.2), 20),
      maxVUs: Math.max(Math.ceil(kvRate * 1.5 * 0.6), 50),
    });
  }
}

export var options: Partial<Options> = {
  scenarios: scenarios,
  noConnectionReuse: false,
  insecureSkipTLSVerify: false,
};

// --- Setup: authenticate and seed test data ---
export function setup(): SetupData {
  console.log('Authenticating against staging server...');
  var token = authenticate();
  console.log('Authentication successful.');

  console.log('Seeding test data for region ' + REGION + '...');
  var data = seedAll(token);
  console.log('Setup complete. Starting load test.');

  return data;
}

// --- Summary handler: output structured JSON for comparison ---
export function handleSummary(data: any): Record<string, string> {
  var result: any = {
    region: REGION,
    commit: COMMIT_SHA,
    timestamp: new Date().toISOString(),
    metrics: {},
  };

  for (var ni = 0; ni < ALL_NAMES.length; ni++) {
    var name = ALL_NAMES[ni];
    var durKey = name + '_duration';
    var errKey = name + '_errors';
    var itrKey = name + '_iters';

    var dur = data.metrics[durKey];
    var err = data.metrics[errKey];
    var itr = data.metrics[itrKey];

    if (dur && itr && itr.values.count > 0) {
      result.metrics[name] = {
        p50: dur.values.med || 0,
        p95: dur.values['p(95)'] || 0,
        p99: dur.values['p(99)'] || 0,
        avg: dur.values.avg || 0,
        min: dur.values.min || 0,
        max: dur.values.max || 0,
        throughput: itr.values.rate || 0,
        iterations: itr.values.count || 0,
        error_rate: err ? (err.values.rate || 0) : 0,
      };
    }
  }

  return {
    'result.json': JSON.stringify(result, null, 2),
  };
}
