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
      ...new Map(
        samples.filter((s) => Number.isFinite(s.offset_ms) && s.offset_ms >= 0).map((s) => [s.offset_ms, s]),
      ).values(),
    ].sort((a, b) => a.offset_ms - b.offset_ms);
    const intervals = this.samples
      .slice(1)
      .map((s, i) => s.offset_ms - this.samples[i].offset_ms)
      .sort((a, b) => a - b);
    this.maxGap = Math.max(2500, (intervals[Math.floor(intervals.length / 2)] || 1000) * 3);
    this.tracks = [
      { key: "cpu", fields: ["cpu_usage_percent"], names: [], unit: "%", divisor: 1, max: 100 },
      {
        key: "memory",
        fields: ["memory_used_bytes"],
        names: [],
        unit: "GB",
        divisor: GB,
        max: this.maximum(["memory_total_bytes"]),
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
    ctx.strokeStyle = colors.border;
    ctx.globalAlpha = 0.45;
    const ticks = Math.max(2, Math.min(8, Math.floor(plotWidth / 100)));
    for (let i = 0; i <= ticks; i++) {
      const px = inset + (i / ticks) * plotWidth;
      ctx.beginPath();
      ctx.moveTo(px, 0);
      ctx.lineTo(px, height);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    const samples = this.visible(range);
    track.fields.forEach((field, index) => {
      ctx.strokeStyle = ctx.fillStyle = index ? colors.metricSecondary : colors.metricPrimary;
      ctx.lineWidth = 1.5;
      let previous;
      for (const sample of samples) {
        if (!Number.isFinite(sample[field])) {
          previous = null;
          continue;
        }
        const px = x(sample.offset_ms),
          py = y(sample[field]);
        if (previous && sample.offset_ms - previous.offset_ms <= this.maxGap) {
          const prevX = x(previous.offset_ms),
            prevY = y(previous[field]);
          ctx.globalAlpha = 0.12;
          ctx.beginPath();
          ctx.moveTo(prevX, height);
          ctx.lineTo(prevX, prevY);
          ctx.lineTo(px, py);
          ctx.lineTo(px, height);
          ctx.closePath();
          ctx.fill();
          ctx.globalAlpha = 1;
          ctx.beginPath();
          ctx.moveTo(prevX, prevY);
          ctx.lineTo(px, py);
          ctx.stroke();
        }
        ctx.beginPath();
        ctx.arc(px, py, 1.5, 0, Math.PI * 2);
        ctx.fill();
        previous = sample;
      }
    });
    ctx.restore();
  }
}
