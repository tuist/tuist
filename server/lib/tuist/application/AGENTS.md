# Application Supervision

- `WebSupervisor` starts Oban without consumers, then Phoenix, then starts the configured queues locally. Phoenix drains requests before Oban shuts down.
- Keep these children under `:rest_for_one` so an Oban restart also restarts the endpoint and starts queues. Preserve explicitly paused queues.
- `RuntimeChildren` derives role-specific children without starting processes.

The queue startup sequence follows [Oban maintainer guidance](https://elixirforum.com/t/do-pause-semantics-in-oban-queue-configuration-apply-locally-or-globally/74115/2).

Use `Oban.start_queue/2` after endpoint startup so a restarted queue retains its original pause setting. Metrics read configured queues from application configuration because consumers start dynamically.
