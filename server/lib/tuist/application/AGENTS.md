# Application Supervision

- Keep the endpoint before Oban so workers can access endpoint configuration throughout startup and shutdown. Keep queues in Oban's configuration so its internal supervisors can restore consumers.
- `Tuist.Application.prep_stop/1` calls `EndpointDrainer` before the application supervision tree stops. It drains Phoenix sockets and Bandit connections while Oban and endpoint configuration remain available.
- Drain socket transports before the Bandit servers, following Phoenix's shutdown order. Terminate children through their supervisor so they are not restarted; leave endpoint configuration alive for Oban's subsequent job drain.
- `RuntimeChildren` derives role-specific children without starting processes.

Use the standard [application shutdown callback](https://hexdocs.pm/elixir/Application.html#c:prep_stop/1) and [socket drainer specifications](https://hexdocs.pm/phoenix/Phoenix.Socket.Transport.html#c:drainer_spec/1). The server child identifiers follow Bandit's Phoenix adapter.
