import { Options } from 'k6/options';
import { REGION, COMMIT_SHA } from './config.ts';
import { ALL_NAMES } from './metrics.ts';
import { authToken } from './lib/auth.ts';
import { seedAll } from './lib/seed.ts';
import { SCENARIO_PLANS, SCENARIO_PLAN_BY_KEY } from './scenario-plan.ts';
import { SetupData } from './types.ts';

export {
  xcodeRead10kb,
  xcodeRead256kb,
  xcodeRead2mb,
  xcodeWrite10kb,
  xcodeWrite256kb,
  xcodeWrite2mb,
} from './scenarios/xcode.ts';
export {
  moduleExists5mb,
  moduleExists10mb,
  moduleExists25mb,
  moduleRead5mb,
  moduleRead10mb,
  moduleRead25mb,
  moduleWrite5mb,
  moduleWrite10mb,
  moduleWrite25mb,
} from './scenarios/module.ts';
export {
  gradleRead5mb,
  gradleRead10mb,
  gradleRead25mb,
  gradleWrite5mb,
  gradleWrite10mb,
  gradleWrite25mb,
} from './scenarios/gradle.ts';
export { keyValueRead, keyValueWrite } from './scenarios/kv.ts';

// --- Scenario builder ---
//
// Each reported metric now maps 1:1 to a dedicated scenario. That gives us
// deterministic iteration budgets per metric instead of relying on weighted
// random bucket selection inside a shared scenario.

interface ScenarioConfig {
  exec: string;
  rate: number;
  duration: number;
  expectedLatencyMs: number;
  startTime: string;
  preAllocatedVUs?: number;
  maxVUs?: number;
}

function makeScenario(cfg: ScenarioConfig): any {
  const expectedConcurrentVUs = Math.ceil((cfg.rate * cfg.expectedLatencyMs) / 1000);
  const preAllocatedVUs = cfg.preAllocatedVUs ?? Math.max(Math.ceil(expectedConcurrentVUs * 1.5), 1);
  const maxVUs = cfg.maxVUs ?? Math.max(preAllocatedVUs * 2, preAllocatedVUs + 2);

  return {
    executor: 'constant-arrival-rate',
    exec: cfg.exec,
    rate: cfg.rate,
    timeUnit: '1s',
    duration: `${cfg.duration}s`,
    preAllocatedVUs,
    maxVUs,
    startTime: cfg.startTime,
  };
}

// --- Build k6 options (scenarios run sequentially) ---

const scenarios: Record<string, any> = {};
let offset = 0;
for (const plan of SCENARIO_PLANS) {
  scenarios[plan.key] = makeScenario({
    exec: plan.exec,
    rate: plan.rate,
    duration: plan.duration,
    expectedLatencyMs: plan.expectedLatencyMs,
    startTime: `${offset}s`,
    preAllocatedVUs: plan.preAllocatedVUs,
    maxVUs: plan.maxVUs,
  });
  offset += plan.duration;
}

export const options: Partial<Options> = {
  scenarios,
  setupTimeout: '10m',
  discardResponseBodies: true,
  noConnectionReuse: false,
  insecureSkipTLSVerify: false,
};

// --- Setup: authenticate and seed test data ---

export function setup(): SetupData {
  console.log(`Using cache project token for region ${REGION}.`);
  const token = authToken();

  console.log(`Seeding test data for region ${REGION}...`);
  const data = seedAll(token);
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
    const plan = SCENARIO_PLAN_BY_KEY[name];
    const dur = data.metrics[`${name}_duration`];
    const err = data.metrics[`${name}_errors`];
    const itr = data.metrics[`${name}_iters`];

    if (!plan) continue;

    const iterations = itr?.values.count ?? 0;

    result.metrics[name] = {
      p50: dur?.values.med ?? 0,
      p95: dur?.values['p(95)'] ?? 0,
      p99: dur?.values['p(99)'] ?? 0,
      avg: dur?.values.avg ?? 0,
      min: dur?.values.min ?? 0,
      max: dur?.values.max ?? 0,
      throughput: iterations / plan.duration,
      iterations,
      min_iterations: plan.minIterations,
      target_iterations: plan.rate * plan.duration,
      error_rate: err ? (err.values.rate ?? 0) : 0,
    };
  }

  return { 'result.json': JSON.stringify(result, null, 2) };
}
