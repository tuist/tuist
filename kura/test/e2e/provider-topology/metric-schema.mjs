// Prometheus omits an entire empty Family, including TYPE. Only these two
// source-verified lazy Counter families may therefore start without samples.
const families = [
  ["kura_memory_pressure_transitions_total", "memory_pressure_transitions", "MemoryPressureTransitionLabels"],
  ["kura_segment_refresh_bytes_total", "segment_refresh_bytes", "SegmentRefreshLabels"],
];
export const lazyCounterNames = families.map(([name]) => name + "_total");
export function knownLazyCounters(source) {
  return families.map(([name, field, labels]) => {
    const declaration = new RegExp(`let\\s+${field}\\s*=\\s*Family::<${labels},\\s*Counter>::default\\(\\);`);
    const registration = new RegExp(`registry\\.register\\(\\s*"${name}",\\s*"[^"]*",\\s*${field}\\.clone\\(\\),\\s*\\);`);
    if (!declaration.test(source) || !registration.test(source)) throw Error(`unqualified lazy counter schema: ${name}`);
    return name + "_total";
  });
}
