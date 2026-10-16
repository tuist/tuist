import assert from "node:assert/strict";
import { createHash } from "node:crypto";

export const GiB = 1024 ** 3;
// Anonymous aggregate sizes from the retained index observed on 2026-10-16.
// No original keys, namespaces, digests or bodies are part of this fixture.
const histogram = [
  [54591, 20588009],
  [31809, 71191948],
  [31530, 280483675],
  [21489, 677259073],
  [6810, 856132931],
  [3239, 1694354024],
  [1229, 2650054575],
  [967, 7107688464],
  [188, 5984385230],
  [19, 1798150395],
  [36, 6781366806],
  [36, 16964122021],
];
export function profile(name) {
  assert(["smoke", "production"].includes(name), "unknown profile");
  const production = name === "production";
  const sizes = [];
  for (const [count, total] of production
    ? histogram
    : [
        [256, 256 * 16384],
        [32, 32 * 1048576],
      ]) {
    let remaining = total,
      records = count;
    // Preserve the large-body tail, which a mean-size workload loses.
    if (production && count === 36 && total === 16964122021) {
      for (const size of [
        814310767, 814310767, 814310767, 559154425, 559154425,
      ]) {
        sizes.push(size);
        remaining -= size;
        records--;
      }
    }
    for (; records; records--) {
      const size = Math.floor(remaining / records);
      sizes.push(size);
      remaining -= size;
    }
  }
  // Stable shuffle prevents a size-sorted corpus from changing ring retention.
  let random = 981731;
  for (let i = sizes.length - 1; i > 0; i--) {
    random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
    const j = random % (i + 1);
    [sizes[i], sizes[j]] = [sizes[j], sizes[i]];
  }
  // Put the observed largest bodies in the oldest retained segments so the
  // fragmented case exercises their repair, not just small metadata-heavy holes.
  if (production)
    for (let i = 0; i < 3; i++) {
      const j = sizes.findIndex((size, n) => n >= i && size === 814310767);
      [sizes[i], sizes[j]] = [sizes[j], sizes[i]];
    }
  return {
    name,
    sizes,
    actions: production ? 77017 : 128,
    capacity: production ? 57804891095 : 3 * GiB,
    volume: production ? "64Gi" : "8Gi",
    historyBytes: production ? 20 * GiB : 0,
    divergenceBytes: production ? 9 * GiB : 16 * 1048576,
    fillerSize: production ? 128 * 1048576 : 1048576,
    peerBytesPerSecond: 62500000,
    deadlineMs: 300000,
  };
}
const fill = Buffer.alloc(64 * 1024, 73);
export function* bodyChunks(id, size) {
  assert(Number.isSafeInteger(size) && size >= 16);
  const prefix = createHash("sha256")
    .update(String(id))
    .digest()
    .subarray(0, 16);
  yield prefix;
  for (
    let remaining = size - prefix.length;
    remaining > 0;
    remaining -= fill.length
  )
    yield fill.subarray(0, Math.min(remaining, fill.length));
}
export function bodyHash(id, size) {
  const hash = createHash("sha256");
  for (const chunk of bodyChunks(id, size)) hash.update(chunk);
  return hash.digest("hex");
}
export function classify(result, sourceLog, targetLog) {
  if (
    result.error ||
    !result.setupVerified ||
    !result.sourceResumed ||
    result.barrier
  )
    return "not-reproduced";
  const events = (log) =>
    log.split("\n").flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch {
        return [];
      }
    });
  const failed = events(sourceLog).filter(
    (e) => e["event.name"] === "kura.handover.failed",
  );
  const revisits = events(targetLog).filter(
    (e) => e["event.name"] === "kura.handover.repair_revisit",
  );
  result.sourceFailures = failed.length;
  result.repairRevisits = revisits.length;
  // A timeout or setup error by itself must never count as reproducing churn.
  return result.profile === "production" &&
    result.shape?.missingBytes >= 1e9 &&
    result.shape?.missingBytes <= 5e9 &&
    result.handoverMs >= 300000 &&
    failed.length >= 2 &&
    revisits.length >= 2 &&
    result.requestTimeouts >= 2
    ? "repair-timeout"
    : "not-reproduced";
}

export function runtimeResources(p) {
  return {
    requests: {
      cpu: "600m",
      memory: "1Gi",
      "ephemeral-storage": p.volume,
      "tuist.dev/memory-ceiling-mib": "4096",
    },
    limits: { cpu: "4", memory: "4Gi", "tuist.dev/memory-ceiling-mib": "4096" },
  };
}

export function* seedBatches(sizes) {
  let batch = [],
    bytes = 0;
  for (let i = 0; i < sizes.length; i++) {
    if (
      batch.length &&
      (batch.length === 32 || bytes + sizes[i] > 128 * 1048576)
    ) {
      yield batch;
      batch = [];
      bytes = 0;
    }
    batch.push(i);
    bytes += sizes[i];
  }
  if (batch.length) yield batch;
}

export function missingShape(records, present) {
  const missing = records.filter((record) => !present.has(record.record_id));
  return {
    missingBlobs: missing.length,
    missingBytes: missing.reduce((sum, record) => sum + record.size, 0),
    missingLargeBlobs: missing.filter((record) => record.size >= 750e6).length,
  };
}

export function fragmentationReady(shape) {
  return (
    shape.missingBytes >= 2.4e9 &&
    shape.missingBytes <= 5e9 &&
    shape.missingLargeBlobs >= 1
  );
}
