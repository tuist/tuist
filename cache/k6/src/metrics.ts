import { Trend, Rate, Counter } from 'k6/metrics';
import { XCODE_SIZES, LARGE_SIZES } from './config.ts';

export interface FlowMetrics {
  duration: Trend;
  errors: Rate;
  iters: Counter;
}

function create(name: string): FlowMetrics {
  return {
    duration: new Trend(name + '_duration', true),
    errors: new Rate(name + '_errors'),
    iters: new Counter(name + '_iters'),
  };
}

const xcodeSizeNames = XCODE_SIZES.map(function (s) { return s.name; });
const largeSizeNames = LARGE_SIZES.map(function (s) { return s.name; });

const ALL_NAMES: string[] = ([] as string[]).concat(
  ['kv_get', 'kv_put', 'kv_sat_get', 'kv_sat_put'],
  xcodeSizeNames.reduce(function (acc: string[], s: string) {
    acc.push('xcode_read_hit_' + s, 'xcode_write_' + s);
    return acc;
  }, []),
  largeSizeNames.reduce(function (acc: string[], s: string) {
    acc.push('module_exists_' + s, 'module_read_hit_' + s, 'module_write_' + s);
    return acc;
  }, []),
  largeSizeNames.reduce(function (acc: string[], s: string) {
    acc.push('gradle_read_hit_' + s, 'gradle_write_' + s);
    return acc;
  }, [])
);

export const metrics: Record<string, FlowMetrics> = {};
for (var i = 0; i < ALL_NAMES.length; i++) {
  metrics[ALL_NAMES[i]] = create(ALL_NAMES[i]);
}

export function record(name: string, duration: number, success: boolean): void {
  var m = metrics[name];
  if (!m) return;
  m.duration.add(duration);
  m.errors.add(success ? 0 : 1);
  m.iters.add(1);
}

export { ALL_NAMES };
