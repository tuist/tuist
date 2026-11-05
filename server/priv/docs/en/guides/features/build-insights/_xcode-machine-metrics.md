## Machine metrics {#machine-metrics}

Build insights can include machine-level performance metrics (CPU, memory, network, and disk usage) captured during the build. To enable this, set up a lightweight background daemon that continuously samples system metrics:

```bash
tuist setup insights
```

This runs a local daemon that samples metrics in the background. The data is picked up automatically by `tuist inspect build` and uploaded with the build report.

> [!TIP]
> **CI**
>
> Run `tuist setup insights` on your CI machines before building to capture machine metrics there as well.

To stop collecting machine metrics, run:

```bash
tuist teardown insights
```

This unloads the daemon's LaunchAgent, removes its plist, and deletes the sampled metrics and daemon logs from `~/.local/state`, so nothing is left running in the background.
