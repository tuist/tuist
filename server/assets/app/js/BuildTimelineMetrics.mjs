const GB = 1e9;
const MIB = 1024 * 1024;

function lowerBound(samples, time) {
  let low = 0,
    high = samples.length;
  while (low < high) {
    const mid = (low + high) >>> 1;
    if (samples[mid].offset_ms < time) low = mid + 1;
    else high = mid;
  }
  return low;
}

export class TimelineMetrics {
  constructor(samples, labels = { in: "In", out: "Out", read: "Read", write: "Write" }) {
    this.samples = [
      ...new Map(samples.filter((s) => Number.isFinite(s.offset_ms)).map((s) => [s.offset_ms, s])).values(),
    ].sort((a, b) => a.offset_ms - b.offset_ms);
    const intervals = this.samples
      .slice(1)
      .map((s, i) => s.offset_ms - this.samples[i].offset_ms)
      .sort((a, b) => a - b);
    this.maxGap = Math.max(2500, (intervals[Math.floor(intervals.length / 2)] || 1000) * 3);
    const cpuCores =
      !this.samples.some((s) => Number.isFinite(s.cpu_usage_percent)) &&
      this.samples.some((s) => Number.isFinite(s.cpu_usage_cores));
    this.tracks = [
      {
        key: "cpu",
        fields: [cpuCores ? "cpu_usage_cores" : "cpu_usage_percent"],
        names: [],
        unit: cpuCores ? labels.cores || "cores" : "%",
        divisor: 1,
        max: cpuCores ? this.maximum(["cpu_usage_cores"]) : 100,
      },
      {
        key: "memory",
        fields: ["memory_used_bytes"],
        names: [],
        unit: "GB",
        divisor: GB,
        max: this.maximum(["memory_total_bytes", "memory_used_bytes"]),
      },
      {
        key: "network",
        fields: ["network_bytes_in", "network_bytes_out"],
        names: [labels.in, labels.out],
        unit: "MiB/s",
        divisor: MIB,
        max: this.maximum(["network_bytes_in", "network_bytes_out"]),
      },
      {
        key: "disk",
        fields: ["disk_bytes_read", "disk_bytes_written"],
        names: [labels.read, labels.write],
        unit: "MiB/s",
        divisor: MIB,
        max: this.maximum(["disk_bytes_read", "disk_bytes_written"]),
      },
    ];
  }

  maximum(fields) {
    let max = 0;
    for (const sample of this.samples)
      for (const field of fields) if (Number.isFinite(sample[field])) max = Math.max(max, sample[field]);
    return max;
  }

  visible(range) {
    const start = Math.max(0, lowerBound(this.samples, range.start) - 1);
    const end = Math.min(this.samples.length, lowerBound(this.samples, range.start + range.span) + 1);
    return this.samples.slice(start, end);
  }

  sampleAt(time) {
    const index = lowerBound(this.samples, time);
    const a = this.samples[index - 1],
      b = this.samples[index];
    if (b?.offset_ms === time) return b;
    if (Number.isFinite(a?.duration_ms)) {
      return time <= a.offset_ms + a.duration_ms ? a : null;
    }
    // Never extend readings beyond collection, or imply measurements in a missing interval.
    if (
      (!a && b?.offset_ms !== time) ||
      (!b && a?.offset_ms !== time) ||
      (a && b && b.offset_ms - a.offset_ms > this.maxGap && b.offset_ms !== time)
    )
      return null;
    return !a || (b && b.offset_ms - time < time - a.offset_ms) ? b : a;
  }

  label(track, time) {
    if (time == null)
      return `0–${(track.max / track.divisor).toLocaleString(undefined, { maximumFractionDigits: 1 })} ${track.unit}`;
    const sample = this.sampleAt(time);
    return track.fields
      .map((field, i) => {
        const value = sample?.[field];
        return `${track.names[i] ? track.names[i] + " " : ""}${Number.isFinite(value) ? (value / track.divisor).toLocaleString(undefined, { maximumFractionDigits: 1 }) + " " + track.unit : "—"}`;
      })
      .join(" · ");
  }

  draw(ctx, width, height, track, range, colors) {
    ctx.clearRect(0, 0, width, height);
    const inset = 12,
      plotWidth = width - 2 * inset;
    const x = (time) => inset + ((time - range.start) / range.span) * plotWidth;
    const y = (value) => height - 3 - Math.max(0, Math.min(1, value / Math.max(1, track.max))) * (height - 6);
    ctx.save();
    ctx.beginPath();
    ctx.rect(inset, 0, plotWidth, height);
    ctx.clip();
    ctx.strokeStyle = colors.grid;
    ctx.globalAlpha = 1;
    for (let i = 0; i <= 4; i++) {
      const py = y((track.max * i) / 4);
      ctx.beginPath();
      ctx.moveTo(inset, py);
      ctx.lineTo(width - inset, py);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    const samples = this.visible(range);
    track.fields.forEach((field, index) => {
      ctx.strokeStyle = ctx.fillStyle = index ? colors.metricSecondary : colors.metricPrimary;
      ctx.lineWidth = 2;
      let previous;
      for (const sample of samples) {
        if (!Number.isFinite(sample[field])) {
          previous = null;
          continue;
        }
        const px = x(sample.offset_ms),
          py = y(sample[field]);
        if (Number.isFinite(sample.duration_ms) && sample.duration_ms > 0) {
          ctx.beginPath();
          if (Math.abs(previous?.offset_ms + previous?.duration_ms - sample.offset_ms) < 0.001) {
            ctx.moveTo(px, y(previous[field]));
            ctx.lineTo(px, py);
          }
          ctx.moveTo(px, py);
          ctx.lineTo(x(sample.offset_ms + sample.duration_ms), py);
          ctx.stroke();
          // Counter buckets are interval aggregates, not interpolated point readings.
          previous = sample;
          continue;
        }
        if (previous && sample.offset_ms - previous.offset_ms <= this.maxGap) {
          const prevX = x(previous.offset_ms),
            prevY = y(previous[field]);
          ctx.beginPath();
          ctx.moveTo(prevX, prevY);
          ctx.lineTo(px, py);
          ctx.stroke();
        }
        if (samples.length < plotWidth / 8) {
          ctx.beginPath();
          ctx.arc(px, py, 2, 0, Math.PI * 2);
          ctx.fill();
        }
        previous = sample;
      }
    });
    ctx.restore();
  }
}
