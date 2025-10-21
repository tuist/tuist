function isKvHit(result) {
  return result !== null && result !== undefined;
}

class RouteMetricsTracker {
  constructor(routeLabel, request, sampleRate) {
    this.routeLabel = routeLabel;
    this.method = request.method;
    this.sampleRate = sampleRate;
    this.start = performance.now();
    this.originMs = 0;
    this.kvReadMs = 0;
    this.kvWriteMs = 0;
    this.kvReadCount = 0;
    this.kvWriteCount = 0;
    this.kvHitCount = 0;
    this.s3FetchMs = 0;
    this.s3FetchCount = 0;
    this.serverFetchMs = 0;
    this.serverFetchCount = 0;
    this.helpers = null;
  }

  wrapFetch(fetchFn = fetch) {
    return async (...args) => {
      const start = performance.now();
      try {
        return await fetchFn(...args);
      } finally {
        this.originMs += performance.now() - start;
      }
    };
  }

  wrapEnv(env) {
    if (!env || typeof env !== "object") return env;

    const instrumentedEnv = Object.create(env);

    if (env.CAS_CACHE && typeof env.CAS_CACHE === "object") {
      instrumentedEnv.CAS_CACHE = this.wrapKvNamespace(env.CAS_CACHE);
    }

    return instrumentedEnv;
  }

  wrapKvNamespace(namespace) {
    const tracker = this;

    return new Proxy(namespace, {
      get(target, prop, receiver) {
        const value = Reflect.get(target, prop, receiver);

        if (prop === "get" && typeof value === "function") {
          return async function wrappedGet(...args) {
            const start = performance.now();
            try {
              const result = await value.apply(target, args);
              tracker.recordKvRead(performance.now() - start, result, false);
              return result;
            } catch (error) {
              tracker.recordKvRead(performance.now() - start, null, true);
              throw error;
            }
          };
        }

        if (prop === "put" && typeof value === "function") {
          return async function wrappedPut(...args) {
            const start = performance.now();
            try {
              return await value.apply(target, args);
            } finally {
              tracker.recordKvWrite(performance.now() - start);
            }
          };
        }

        return value;
      },
    });
  }

  recordKvRead(duration, result, failed) {
    this.kvReadMs += duration;
    this.kvReadCount += 1;
    this.originMs += duration;

    if (failed) {
      return;
    }

    if (isKvHit(result)) {
      this.kvHitCount += 1;
    }
  }

  recordKvWrite(duration) {
    this.kvWriteMs += duration;
    this.kvWriteCount += 1;
    this.originMs += duration;
  }

  async measureServerFetch(fn, category = "server") {
    const start = performance.now();
    try {
      return await fn();
    } finally {
      const duration = performance.now() - start;
      this.originMs += duration;
      if (category === "s3") {
        this.s3FetchMs += duration;
        this.s3FetchCount += 1;
      } else {
        this.serverFetchMs += duration;
        this.serverFetchCount += 1;
      }
    }
  }

  buildHandlerHelpers() {
    if (!this.helpers) {
      this.helpers = {
        fetch: this.wrapFetch(fetch),
        measureServerFetch: (fn, category) =>
          this.measureServerFetch(fn, category),
      };
    }

    return this.helpers;
  }

  flush(env, ctx, response) {
    const totalMs = performance.now() - this.start;
    const computeMs = Math.max(0, totalMs - this.originMs);

    if (!env?.METRICS) {
      return;
    }

    ctx.waitUntil(
      env.METRICS.writeDataPoint({
        indexes: [new Date()],
        blobs: [this.routeLabel, this.method, String(response.status)],
        doubles: [
          totalMs,
          this.originMs,
          computeMs,
          this.sampleRate,
          this.kvReadMs,
          this.kvWriteMs,
          this.s3FetchMs,
          this.serverFetchMs,
          this.kvHitCount,
          this.kvReadCount,
          this.kvWriteCount,
          this.s3FetchCount,
          this.serverFetchCount,
        ],
      }),
    );
  }
}

export function withRouteTiming(routeLabel, handler, opts) {
  const sampleRate =
    opts && opts.sampleRate != null ? opts.sampleRate : 1.0; // 1.0 = 100%

  return async (req, env, ctx) => {
    const doSample = Math.random() < sampleRate;
    const tracker = doSample
      ? new RouteMetricsTracker(routeLabel, req, sampleRate)
      : null;
    const instrumentedEnv = tracker ? tracker.wrapEnv(env) : env;
    const helpers = tracker ? tracker.buildHandlerHelpers() : undefined;

    const res = await handler(req, instrumentedEnv, helpers);

    if (tracker) {
      tracker.flush(env, ctx, res);
    }

    return res;
  };
}
