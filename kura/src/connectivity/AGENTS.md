# Fixed connectivity telemetry

This module observes the pod network path for read-only operators using existing
Kura logs. The controller enables exact instances via `KURA_CONNECTIVITY_PROFILE`.
Only compiled production/staging/canary Service names and GET `/ready` are allowed.

- Keep this optional and independent of application startup/readiness decisions.
  The guard never joins the worker. Dedicated thread/runtime errors must not
  propagate to `app::run`; catch unwinding worker panics. Do not add sidecars.
- Pass no AppState, authenticated client, store, or secret inputs. There is no
  listener, command interface, arbitrary target, or user-triggered sampling.
  The worker shares Kura's process privileges; do not describe it as isolated
  from credentials or process-wide resource failures.
- Preserve one outstanding libc DNS job even when its async waiter times out.
  Hold the permit inside the blocking closure. Runtime shutdown cannot wait for
  an uncancellable resolver call.
- Validate every resolved address before the single dial; no second lookup,
  fallback, redirects, proxies, auth, cookies, or body draining. Preserve fixed
  buffers (8 KiB response, 4 KiB resolver), serial samples, and all deadlines.
- Emit resolver config only on startup/change; never emit response content,
  remote error strings, credentials, or application data.
- Test lifecycle failure/cancellation, profile order/budgets and absolute Host,
  mixed unsafe DNS answers, shared DNS/TCP deadlines, stuck DNS and HTTP bounds.
  Use local sockets/injected resolver operations; never require cluster access.
- Keep `infra/kura-controller/connectivity-diagnostics.md`, Kura README and
  architecture documentation accurate when these boundaries change.
