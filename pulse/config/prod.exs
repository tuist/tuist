import Config

# Do not print debug messages in production
config :logger, level: :info

# A sentinel that runtime.exs is expected to overwrite. If a release starts
# without runtime.exs having populated the real auth module, `Pulse.Auth`
# raises rather than serving requests with the Open (accept-everything)
# fallback that ships in config.exs.
config :pulse, Pulse.Auth, module: :must_configure_at_runtime

# No `force_ssl`: Pulse serves plain HTTP behind a TLS-terminating proxy or
# ingress. Phoenix applies `force_ssl` at compile time, so it would redirect
# every in-cluster request (collectors, scrapes, orchestrator probes) whose
# Host is not localhost. Redirecting an API call also protects nothing: the
# bearer token has already crossed the wire by the time the redirect is sent.
# Terminate TLS in front of Pulse and keep its listener off public networks.

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
