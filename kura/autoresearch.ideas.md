# Kura bounded-resource optimization ideas

- Remove the private `SegmentReader` vector-to-caller copy by exposing owned chunks.
- Measure Tokio blocking-pool dispatch after copy removal before evaluating a ring-based file runtime.
- Move accelerated-serving candidate fields instead of cloning the file handle, content type, namespace, analytics key, and tenant.
- Move accelerated request headers and query parameters into authorization instead of cloning their complete maps.
- Audit response-stream memory multipliers after every proven buffer removal.
- Measure whether one-chunk read-ahead improves cold-disk throughput enough to justify its extra bounded buffer.
- Audit manifest and handle cache key ownership for duplicate strings retained across indexes.
