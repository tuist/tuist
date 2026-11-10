## Machine metrics {#machine-metrics}

Build insights can include machine-level performance metrics (CPU, memory, network, and disk usage) captured during the build. To enable this, set up a lightweight background daemon that continuously samples system metrics:

```bash
tuist setup insights
```

This runs a local daemon that samples metrics in the background. The data is picked up automatically by `tuist inspect build` and uploaded with the build report.

Disk metrics include read/write activity and, with a compatible CLI and server, total and available space on the macOS system Data volume (`/System/Volumes/Data`). Available space excludes purgeable space. The Disk space chart shows used space (total minus available) alongside total capacity over the build, not just at upload time. It does not measure separate external volumes used for a checkout or DerivedData.

After upgrading the CLI, restart an existing sampler with `tuist teardown insights` followed by `tuist setup insights`. Sampling must be running during the build; older reports and failed measurements have no disk-space values and are not shown as zero. Disk-space samples follow the existing 90-day machine-metrics retention.

> [!TIP]
> **CI**
>
> Run `tuist setup insights` on your CI machines before building to capture machine metrics there as well.

To stop collecting machine metrics, run:

```bash
tuist teardown insights
```

This unloads the daemon's LaunchAgent, removes its plist, and deletes the sampled metrics and daemon logs from `~/.local/state`, so nothing is left running in the background.
