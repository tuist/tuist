import { Options } from 'k6/options';
import { REGION, COMMIT_SHA } from './config.ts';
import { ALL_NAMES } from './metrics.ts';
import { authenticate } from './lib/auth.ts';
import { seedAll } from './lib/seed.ts';
import { SetupData } from './types.ts';



// --- Re-export scenario functions so k6 can call them by name ---
export { xcodeRead, xcodeWrite } from './scenarios/xcode.ts';
export { moduleExists, moduleRead, moduleWrite } from './scenarios/module.ts';
export { gradleRead, gradleWrite } from './scenarios/gradle.ts';
export { keyValueRead, keyValueWrite } from './scenarios/kv.ts';

// --- Scenario builder ---
interface ScenarioConfig {
  exec: string;
  rate: number;
  startTime?: string;
  preAllocatedVUs?: number;
  maxVUs?: number;
}

var SCENARIO_SECONDS = 150; // each scenario runs for 2m30s

function makeScenario(cfg: ScenarioConfig): any {
  var halfRate = Math.ceil(cfg.rate * 0.5);
  var fullRate = cfg.rate;
  var burstRate = Math.ceil(cfg.rate * 1.5);

  return {
    executor: 'ramping-arrival-rate',
    exec: cfg.exec,
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: cfg.preAllocatedVUs || Math.max(Math.ceil(burstRate * 0.02), 5),
    maxVUs: cfg.maxVUs || Math.max(Math.ceil(burstRate * 0.2), 10),
    startTime: cfg.startTime || '0s',
    stages: [
      { duration: '15s', target: halfRate },
      { duration: '30s', target: halfRate },
      { duration: '10s', target: fullRate },
      { duration: '1m', target: fullRate },
      { duration: '10s', target: burstRate },
      { duration: '25s', target: burstRate },
    ],
  };
}

// --- Build k6 options (scenarios run sequentially) ---
var scenarios: Record<string, any> = {};

var allEntries = [
  { key: 'key_value_read', exec: 'keyValueRead', rate: 1024 },
  { key: 'key_value_write', exec: 'keyValueWrite', rate: 512 },
  { key: 'xcode_read', exec: 'xcodeRead', rate: 1024 },
  { key: 'xcode_write', exec: 'xcodeWrite', rate: 1024 },
  { key: 'module_exists', exec: 'moduleExists', rate: 128 },
  { key: 'module_read', exec: 'moduleRead', rate: 256 },
  { key: 'module_write', exec: 'moduleWrite', rate: 16 },
  { key: 'gradle_read', exec: 'gradleRead', rate: 256 },
  { key: 'gradle_write', exec: 'gradleWrite', rate: 16 },
];

var offset = 0;
for (var i = 0; i < allEntries.length; i++) {
  var entry = allEntries[i];
  if (entry.rate) {
    scenarios[entry.key] = makeScenario({
      exec: entry.exec,
      rate: entry.rate,
      startTime: offset + 's',
    });
    offset += SCENARIO_SECONDS;
  }
}

export var options: Partial<Options> = {
  scenarios: scenarios,
  setupTimeout: '15m',
  discardResponseBodies: true,
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
