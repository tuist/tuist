# Application Supervision

- Keep the endpoint before Oban so workers can access endpoint configuration throughout startup and shutdown. Keep queues in Oban's configuration so its internal supervisors can restore consumers.
- `Tuist.Application.prep_stop/1` calls `EndpointDrainer` before the application supervision tree stops. It drains Phoenix sockets and Bandit connections while Oban and endpoint configuration remain available.
- Drain socket transports before the Bandit servers, following Phoenix's shutdown order. Terminate children through their supervisor so they are not restarted; leave endpoint configuration alive for Oban's subsequent job drain.
- `RuntimeChildren` derives role-specific children without starting processes.
- Startup references across the application boundary require exports in `Tuist`,
  including `ClickHouseRepo.PromExPlugin` for read-telemetry attachment.
- Ecto tracing covers the primary Postgres, Cloud read/ingest, ops ClickHouse,
  and both shadow repositories. Dynamic read routing emits the physical shadow
  repository's event prefix, not the logical read repository's prefix.

Use the standard [application shutdown callback](https://hexdocs.pm/elixir/Application.html#c:prep_stop/1) and [socket drainer specifications](https://hexdocs.pm/phoenix/Phoenix.Socket.Transport.html#c:drainer_spec/1). The server child identifiers follow Bandit's Phoenix adapter.

## Replica-safety rollout

Start optional-task supervision before the endpoint, but place its drainer after the endpoint so endpoint configuration remains available while tasks finish. The drainer waits at most ten seconds (twelve-second child shutdown budget); owned tasks are not detached `Task.start` processes. Boot Kura reconciliation is enqueued through the existing unique Oban worker instead of running once in every boot task.
