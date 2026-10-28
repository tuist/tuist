# Alerts

- The `:cache_hit_rate` category averages two sources, module cache and Xcode cache. The current and previous windows must be built from the same set of sources and from equally sized samples, otherwise the comparison measures window composition rather than a regression. `Tuist.Cache.Analytics.cache_hit_rate_metric_window_comparison/4` owns that rule; go through it rather than querying either source per window.
