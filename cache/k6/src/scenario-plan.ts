export interface ScenarioPlan {
  key: string;
  exec: string;
  rate: number;
  duration: number;
  expectedLatencyMs: number;
  minIterations: number;
  preAllocatedVUs?: number;
  maxVUs?: number;
}

export const SCENARIO_PLANS: ScenarioPlan[] = [
  { key: 'key_value_read', exec: 'keyValueRead', rate: 256, duration: 8, expectedLatencyMs: 20, minIterations: 1900 },
  { key: 'key_value_write', exec: 'keyValueWrite', rate: 128, duration: 8, expectedLatencyMs: 25, minIterations: 950 },

  { key: 'xcode_read_10kb', exec: 'xcodeRead10kb', rate: 160, duration: 6, expectedLatencyMs: 30, minIterations: 900 },
  { key: 'xcode_read_256kb', exec: 'xcodeRead256kb', rate: 80, duration: 6, expectedLatencyMs: 40, minIterations: 450 },
  { key: 'xcode_read_2mb', exec: 'xcodeRead2mb', rate: 25, duration: 8, expectedLatencyMs: 80, minIterations: 180 },

  { key: 'xcode_write_10kb', exec: 'xcodeWrite10kb', rate: 80, duration: 6, expectedLatencyMs: 40, minIterations: 450 },
  { key: 'xcode_write_256kb', exec: 'xcodeWrite256kb', rate: 30, duration: 8, expectedLatencyMs: 90, minIterations: 220 },
  { key: 'xcode_write_2mb', exec: 'xcodeWrite2mb', rate: 8, duration: 12, expectedLatencyMs: 500, minIterations: 90 },

  { key: 'module_exists_5mb', exec: 'moduleExists5mb', rate: 50, duration: 5, expectedLatencyMs: 20, minIterations: 230 },
  { key: 'module_read_5mb', exec: 'moduleRead5mb', rate: 60, duration: 10, expectedLatencyMs: 150, minIterations: 540, preAllocatedVUs: 64, maxVUs: 128 },
  { key: 'gradle_read_5mb', exec: 'gradleRead5mb', rate: 60, duration: 10, expectedLatencyMs: 1000, minIterations: 540, preAllocatedVUs: 96, maxVUs: 192 },
  { key: 'module_write_5mb', exec: 'moduleWrite5mb', rate: 6, duration: 30, expectedLatencyMs: 6000, minIterations: 160, preAllocatedVUs: 48, maxVUs: 96 },
  { key: 'gradle_write_5mb', exec: 'gradleWrite5mb', rate: 6, duration: 25, expectedLatencyMs: 2500, minIterations: 135, preAllocatedVUs: 24, maxVUs: 48 },

  { key: 'module_exists_10mb', exec: 'moduleExists10mb', rate: 25, duration: 5, expectedLatencyMs: 20, minIterations: 115 },
  { key: 'module_read_10mb', exec: 'moduleRead10mb', rate: 14, duration: 15, expectedLatencyMs: 1200, minIterations: 190, preAllocatedVUs: 32, maxVUs: 64 },
  { key: 'gradle_read_10mb', exec: 'gradleRead10mb', rate: 14, duration: 15, expectedLatencyMs: 1200, minIterations: 190, preAllocatedVUs: 32, maxVUs: 64 },
  { key: 'module_write_10mb', exec: 'moduleWrite10mb', rate: 3, duration: 45, expectedLatencyMs: 18000, minIterations: 120, preAllocatedVUs: 80, maxVUs: 160 },
  { key: 'gradle_write_10mb', exec: 'gradleWrite10mb', rate: 3, duration: 35, expectedLatencyMs: 5000, minIterations: 95, preAllocatedVUs: 32, maxVUs: 64 },

  { key: 'module_exists_25mb', exec: 'moduleExists25mb', rate: 10, duration: 5, expectedLatencyMs: 20, minIterations: 45 },
  { key: 'module_read_25mb', exec: 'moduleRead25mb', rate: 10, duration: 20, expectedLatencyMs: 3000, minIterations: 180, preAllocatedVUs: 48, maxVUs: 96 },
  { key: 'gradle_read_25mb', exec: 'gradleRead25mb', rate: 10, duration: 20, expectedLatencyMs: 3000, minIterations: 180, preAllocatedVUs: 48, maxVUs: 96 },
  { key: 'module_write_25mb', exec: 'moduleWrite25mb', rate: 1, duration: 60, expectedLatencyMs: 22000, minIterations: 55, preAllocatedVUs: 48, maxVUs: 96 },
  { key: 'gradle_write_25mb', exec: 'gradleWrite25mb', rate: 1, duration: 60, expectedLatencyMs: 8000, minIterations: 50, preAllocatedVUs: 32, maxVUs: 64 },
];

export const SCENARIO_PLAN_BY_KEY: Record<string, ScenarioPlan> = Object.fromEntries(
  SCENARIO_PLANS.map((plan) => [plan.key, plan]),
) as Record<string, ScenarioPlan>;
