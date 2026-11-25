import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :caller]

config :phoenix, :json_library, Jason

config :symptoms, Oban,
  repo: Symptoms.Repo,
  queues: [pipeline: 2, state: 1, calibration: 1],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 86_400},
    # Jobs left `executing` by a node that died are rescued after 30 minutes
    # (pipeline jobs, with one attempt, are discarded; the next cron run
    # picks up their windows).
    {Oban.Plugins.Lifeline, rescue_after: to_timeout(minute: 30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Symptoms.Pipeline, args: %{window_seconds: 60}},
       {"*/5 * * * *", Symptoms.Pipeline, args: %{window_seconds: 300}},
       {"* * * * *", Symptoms.State},
       {"5 * * * *", Symptoms.Baselines},
       {"15 3 * * *", Symptoms.Calibrate, args: %{task: "source_weights"}},
       {"45 3 * * *", Symptoms.Calibrate, args: %{task: "retention"}},
       {"0 4 * * 1", Symptoms.Calibrate, args: %{task: "threshold"}},
       {"30 4 * * 1", Symptoms.Calibrate, args: %{task: "platt"}},
       {"0 * * * *", Symptoms.Board}
     ]}
  ]

config :symptoms, Symptoms.Repo, migration_timestamps: [type: :utc_datetime_usec]

config :symptoms, SymptomsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: SymptomsWeb.ErrorJSON], layout: false]

config :symptoms,
  ecto_repos: [Symptoms.Repo],
  generators: [timestamp_type: :utc_datetime_usec],
  # Source modules implementing `Symptoms.Sources.Source`, and their options
  # (`config :symptoms, :source_opts, [{module, opts}]`). Test disables them.
  sources: [
    Symptoms.Sources.PulseTraces,
    Symptoms.Sources.PulseLogs,
    Symptoms.Sources.PulseErrors,
    Symptoms.Sources.PulseSpanEdges,
    Symptoms.Sources.PromMetrics,
    Symptoms.Sources.KubernetesEvents,
    Symptoms.Sources.Probes,
    Symptoms.Sources.Presence
  ],
  source_opts: [],
  disabled_sources: [],
  pipeline_delay_seconds: 60,
  detector: [],
  policy: [],
  # Paging stays off until an IRM webhook is configured and enabled.
  paging: [enabled: false],
  api_auth: [],
  # The metrics listener's port; nil starts none.
  metrics_port: nil,
  state: [token_path: "/var/run/secrets/tuist-symptoms-state/token"]

import_config "#{config_env()}.exs"
