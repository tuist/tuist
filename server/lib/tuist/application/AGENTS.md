# Application Supervision

- Start Redis and both persistent limiter clients before the endpoint, Oban and Once gRPC ingress so they outlive traffic and draining jobs. This orders clients, not backend readiness; shared failures follow the explicit limiter policy.
- Keep the endpoint before Oban so workers can access endpoint configuration throughout startup and shutdown. Keep queues in Oban's configuration so its internal supervisors can restore consumers.
- `Tuist.Application.prep_stop/1` calls `EndpointDrainer` before the application supervision tree stops. It drains Phoenix sockets and Bandit connections while Oban and endpoint configuration remain available.
- Drain socket transports before the Bandit servers, following Phoenix's shutdown order. Terminate children through their supervisor so they are not restarted; leave endpoint configuration alive for Oban's subsequent job drain.
- `RuntimeChildren` derives role-specific children without starting processes.
- Start the disposable `Tuist.OpenGraphImages` generation cache before the endpoint. Its Cachex data and per-key claims owner restart together; a restart may fail cold requests transiently, but published images remain available from shared storage.
- Startup references across the application boundary require exports in `Tuist`,
  including `ClickHouseRepo.PromExPlugin` for read-telemetry attachment.
- Ecto tracing covers the primary Postgres, Cloud read/ingest, ops ClickHouse,
  and both shadow repositories. Dynamic read routing emits the physical shadow
  repository's event prefix, not the logical read repository's prefix.

Use the standard [application shutdown callback](https://hexdocs.pm/elixir/Application.html#c:prep_stop/1) and [socket drainer specifications](https://hexdocs.pm/phoenix/Phoenix.Socket.Transport.html#c:drainer_spec/1). The server child identifiers follow Bandit's Phoenix adapter.

- `RuntimeChildren.readiness_server/1` starts `Tuist.Readiness.Plug` on port 9092 for `:xcresult_processor` only, after Oban so it stops first. tart-kubelet probes `GET /ready`, which checks Postgres, ClickHouse (and the shadow ClickHouse when configured) and the `:process_xcresult` queue. Keep the port in sync with `infra/helm/tuist/templates/xcresult-processor-deployment.yaml`.

## Replica-safety rollout

Boot Kura reconciliation is enqueued through the existing unique Oban worker instead of running once in every boot task. Keep best-effort test-ingestion enrichments on the existing detached `Tuist.Tasks` path; they do not require an application-level task supervisor, drainer or extra pod grace. Required analytics buffer shutdown and shadow-write draining retain their existing lifecycles; neither makes acknowledged in-memory staging durable across hard replica loss.
