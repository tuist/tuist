import { Trend, Rate, Counter } from 'k6/metrics';
import { XCODE_SIZES, LARGE_SIZES } from './config.ts';

export interface FlowMetrics {
  duration: Trend;
  errors: Rate;
  iters: Counter;
}

function create(name: string): FlowMetrics {
  return {
    duration: new Trend(`${name}_duration`, true),
    errors: new Rate(`${name}_errors`),
    iters: new Counter(`${name}_iters`),
  };
}

export const ALL_NAMES: string[] = [
  'key_value_read',
  'key_value_write',
  ...XCODE_SIZES.flatMap((s) => [`xcode_read_${s.name}`, `xcode_write_${s.name}`]),
  ...LARGE_SIZES.flatMap((s) => [
    `module_exists_${s.name}`,
    `module_read_${s.name}`,
    `module_write_${s.name}`,
  ]),
  ...LARGE_SIZES.flatMap((s) => [`gradle_read_${s.name}`, `gradle_write_${s.name}`]),
];

export const metrics: Record<string, FlowMetrics> = {};
for (const name of ALL_NAMES) {
  metrics[name] = create(name);
}

export function record(name: string, duration: number, success: boolean): void {
  const m = metrics[name];
  if (!m) return;
  m.duration.add(duration);
  m.errors.add(success ? 0 : 1);
  m.iters.add(1);
}
