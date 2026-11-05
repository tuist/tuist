# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

alias Pulse.Auth.Open

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :filter_parameters, ["password", "sentry_key", "dsn"]

# Phoenix's JSON library: `Pulse.JSON` encodes and decodes in Rust and
# defers to Elixir's built-in `JSON` for anything it cannot match exactly,
# so behavior is `JSON`'s (no Jason dependency; see AGENTS.md conventions).
config :phoenix, :json_library, Pulse.JSON

# Explicit auth default. Environment-specific configs override; prod requires
# a runtime override to `Pulse.Auth.SharedSecret` via runtime.exs — an unset
# release still raises rather than falling back to open access.
# Configure the endpoint
config :pulse, Pulse.Auth, module: Open

config :pulse, PulseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  # Exporters keep HTTP/1.1 connections alive. Bandit's default full GC every
  # fifth request lets each connection process hold several requests' decoded
  # bodies and records as garbage; collect after every ingest request instead.
  http: [http_1_options: [gc_every_n_keepalive_requests: 1]],
  render_errors: [
    formats: [json: PulseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Pulse.PubSub,
  live_view: [signing_salt: "AAeCXBT1"]

config :pulse,
  generators: [timestamp_type: :utc_datetime]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
