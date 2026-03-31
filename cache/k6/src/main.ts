import encoding from 'k6/encoding';
import { Options } from 'k6/options';
import { REGION, COMMIT_SHA } from './config.ts';
import { ALL_NAMES } from './metrics.ts';
import { authToken } from './lib/auth.ts';
import { seedAll, seedDataOf, setupFromSeedData } from './lib/seed.ts';
import { SeedData, SetupData } from './types.ts';

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

const SCENARIO_DURATION_SECONDS = 300;

function makeScenario(cfg: ScenarioConfig): any {
  const halfRate = Math.ceil(cfg.rate * 0.5);
  const burstRate = Math.ceil(cfg.rate * 1.5);

  return {
    executor: 'ramping-arrival-rate',
    exec: cfg.exec,
    startRate: 0,
    timeUnit: '1s',
    preAllocatedVUs: cfg.preAllocatedVUs ?? Math.max(Math.ceil(burstRate * 0.02), 5),
    maxVUs: cfg.maxVUs ?? Math.max(Math.ceil(burstRate * 0.2), 10),
    startTime: cfg.startTime ?? '0s',
    stages: [
      { duration: '30s', target: halfRate },
      { duration: '1m', target: halfRate },
      { duration: '15s', target: cfg.rate },
      { duration: '2m', target: cfg.rate },
      { duration: '15s', target: burstRate },
      { duration: '1m', target: burstRate },
    ],
  };
}

// --- Build k6 options (scenarios run sequentially) ---

const SCENARIO_ENTRIES = [
  { key: 'key_value_read', exec: 'keyValueRead', rate: 512 },
  { key: 'key_value_write', exec: 'keyValueWrite', rate: 256 },
  { key: 'xcode_read', exec: 'xcodeRead', rate: 512 },
  { key: 'xcode_write', exec: 'xcodeWrite', rate: 256 },
  { key: 'module_exists', exec: 'moduleExists', rate: 64 },
  { key: 'module_read', exec: 'moduleRead', rate: 128 },
  { key: 'module_write', exec: 'moduleWrite', rate: 32 },
  { key: 'gradle_read', exec: 'gradleRead', rate: 128 },
  { key: 'gradle_write', exec: 'gradleWrite', rate: 32 },
];

const scenarios: Record<string, any> = {};
let offset = 0;
for (const entry of SCENARIO_ENTRIES) {
  scenarios[entry.key] = makeScenario({
    exec: entry.exec,
    rate: entry.rate,
    startTime: `${offset}s`,
  });
  offset += SCENARIO_DURATION_SECONDS;
}

export const options: Partial<Options> = {
  scenarios,
  setupTimeout: '30m',
  discardResponseBodies: true,
  noConnectionReuse: false,
  insecureSkipTLSVerify: false,
};

// --- Setup: authenticate and seed test data ---

function loadSeedData(): SeedData | null {
  const json = __ENV.SEED_DATA_JSON;
  if (!json) return null;
  return JSON.parse(json) as SeedData;
}

export function setup(): SetupData {
  console.log(`Using cache project token for region ${REGION}.`);
  const token = authToken();

  const existingSeedData = loadSeedData();
  if (existingSeedData) {
    console.log(`Reusing seeded test data for region ${REGION}...`);
    const data = setupFromSeedData(token, existingSeedData);
    console.log('Setup complete. Starting load test.');
    return data;
  }

  console.log(`Seeding test data for region ${REGION}...`);
  const data = seedAll(token);
  console.log(`SEED_DATA_B64=${encoding.b64encode(JSON.stringify(seedDataOf(data)), 'std')}`);
  console.log('Setup complete. Starting load test.');
  return data;
}

// --- Summary handler: output structured JSON for comparison ---

export function handleSummary(data: any): Record<string, string> {
  const result: any = {
    region: REGION,
    commit: COMMIT_SHA,
    timestamp: new Date().toISOString(),
    metrics: {},
  };

  for (const name of ALL_NAMES) {
    const dur = data.metrics[`${name}_duration`];
    const err = data.metrics[`${name}_errors`];
    const itr = data.metrics[`${name}_iters`];

    if (dur && itr && itr.values.count > 0) {
      result.metrics[name] = {
        p50: dur.values.med ?? 0,
        p95: dur.values['p(95)'] ?? 0,
        p99: dur.values['p(99)'] ?? 0,
        avg: dur.values.avg ?? 0,
        min: dur.values.min ?? 0,
        max: dur.values.max ?? 0,
        throughput: itr.values.rate ?? 0,
        iterations: itr.values.count ?? 0,
        error_rate: err ? (err.values.rate ?? 0) : 0,
      };
    }
  }

  return { 'result.json': JSON.stringify(result, null, 2) };
}
