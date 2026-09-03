# Kura bounded-resource optimization ideas

- Measure whether one-chunk read-ahead improves cold-disk throughput enough to justify its extra bounded buffer.
- Measure authorization consultation-lock contention separately for cold misses and cache hits.
- Check whether the response admission turn lock is reached only after bounded immediate admission fails.
- Measure whether sampled recency updates can safely reduce hot-key write-lock pressure without changing eviction quality.
- Measure client connection sharding before changing the per-connection stream ceiling; one protocol connection retains a shared frame state machine regardless of server worker count.
- Evaluate Linux non-waiting positional reads only in a Linux benchmark with a guaranteed fallback for cold or unsupported filesystems.
- Prototype direct reserved-offset segment writes only with hard caps for writable segments, incomplete reservations, wasted bytes, and commit cohorts.
- Measure fixed metadata-method request throughput now that route and metric-family allocation are removed from those paths.
