export function withRouteTiming(routeLabel, handler, opts) {
  const sampleRate = opts && opts.sampleRate != null ? opts.sampleRate : 1.0; // 1.0 = 100%

  return async (req, env, ctx) => {
    const doSample = Math.random() < sampleRate;

    const t0 = performance.now();
    let originMs = 0;

    const timedFetch = async (...args) => {
      const f0 = performance.now();
      const res = await fetch(...args);
      originMs += performance.now() - f0;
      return res;
    };

    const res = await handler(req, env, ctx, { fetch: timedFetch });

    if (doSample) {
      const totalMs = performance.now() - t0;
      const computeMs = Math.max(0, totalMs - originMs);

      ctx.waitUntil(
        env.METRICS.writeDataPoint({
          indexes: [new Date()],
          blobs: [routeLabel, req.method, String(res.status)],
          doubles: [totalMs, originMs, computeMs, sampleRate],
        }),
      );
    }

    return res;
  };
}
