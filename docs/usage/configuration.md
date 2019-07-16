---
name: Configuration
---

# Configuration

## Disable error tracking

By default, Tuist reports unhandled exceptions and bugs anonymously to [Sentry](https://sentry.io). This feature can be disabled by defining the variable `TUIST_ANALYTICS_DISABLED=1` in your environment or passing it when calling Tuist:

```bash
TUIST_ANALYTICS_DISABLED=1 tuist generate
```

Unless it's a strict requirement to use Tuist at your company/project, we recommend keeping the default behavior. When issues arise, it makes it easier to debug them and find the root cause.
