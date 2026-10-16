// A live upload or compaction can disappear between du's directory walk and
// stat. Preserve its measured total and record that race, but do not hide an
// inaccessible volume, missing total, timeout, or other command failure.
export function diskUsage(read) {
  try {
    return { disk: read() };
  } catch (error) {
    const disk = String(error.stdout ?? "");
    const lines = String(error.stderr ?? "")
      .trim()
      .split("\n");
    const vanished =
      /^du: cannot access '\/data\/[^'\r\n]+': No such file or directory$/;
    const races = lines.filter((line) => vanished.test(line));
    if (
      error.status !== 1 ||
      !/^\d+\s+\/data\s*$/.test(disk) ||
      !races.length ||
      !lines.every(
        (line) =>
          vanished.test(line) || line === "command terminated with exit code 1",
      )
    )
      throw error;
    return {
      disk,
      diskSamplingRaces: races.length,
      diskSamplingWarnings: races.slice(0, 8),
    };
  }
}
