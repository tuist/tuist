defmodule Tuist.Environment do
  @moduledoc false

  # Baked at compile time. Production images build with MIX_ENV=prod and
  # then pick a runtime deployment target via TUIST_DEPLOY_ENV (see env/0)
  # so one image can serve canary, staging, or production. Test/dev
  # builds ignore TUIST_DEPLOY_ENV so tests can't accidentally flip into
  # a prod-like mode.
  @compile_env Mix.env()
  @dev_all_locales Application.compile_env(:tuist, :dev_all_locales, false)

  @runtime_envs ~w(prod can stag preview)
  @default_database_schema "public"
  @postgres_identifier_regex ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/
  # Id of the single key every ciphertext was written under before the key
  # ring, so its tag stays `AES.GCM.V1`.
  @legacy_encryption_key_id "V1"
  @encryption_key_id_regex ~r/\A[A-Za-z0-9_.-]{1,32}\z/
  @agent_auth_default_trusted_providers [
    %{
      "issuer" => "https://auth0.openai.com/",
      "jwks_uri" => "https://auth.openai.com/.well-known/jwks.json"
    }
  ]
  @artifact_retention_environment_variables %{
    cache_artifacts: "TUIST_CACHE_ARTIFACT_RETENTION_DAYS",
    app_previews: "TUIST_APP_PREVIEW_RETENTION_DAYS",
    build_archives: "TUIST_BUILD_ARCHIVE_RETENTION_DAYS",
    run_artifacts: "TUIST_RUN_ARTIFACT_RETENTION_DAYS",
    test_attachments: "TUIST_TEST_ATTACHMENT_RETENTION_DAYS",
    shard_bundles: "TUIST_SHARD_BUNDLE_RETENTION_DAYS"
  }

  # Every supported pod role. `mode/0` raises on any other value of
  # TUIST_MODE so a deployment-manifest typo (`processsor`, `ingest`,
  # ...) fails the pod fast at boot rather than landing it in `:web`
  # silently — exactly the failure mode that previously masked the
  # xcresult-processor leader-election bug.
  @modes [:web, :processor, :xcresult_processor, :swift_registry_sync]

  @doc """
  All pod roles `mode/0` may return. Stable list — used by
  `Tuist.Oban.RuntimeConfig` tests to assert that no future role
  accidentally regains leader eligibility or the full crontab.
  """
  def modes, do: @modes

  def env do
    # Gate on the stringified compile env rather than matching the `:prod`
    # atom directly: `@compile_env` is a compile-time literal, so a
    # `:prod <- @compile_env` match trips Elixir's type checker in test/dev
    # builds (and narrowing `env/0` to that literal poisons every caller
    # that compares `env()` against another env atom).
    with "prod" <- Atom.to_string(@compile_env),
         deploy_env when deploy_env in @runtime_envs <- System.get_env("TUIST_DEPLOY_ENV") do
      String.to_existing_atom(deploy_env)
    else
      _ -> @compile_env
    end
  end

  # Long-form name of the current deployment environment, matching what
  # cache/registry/kura already ship and what the Sentry ecosystem
  # expects. Alert rules and dashboards filter on string equality, so
  # every service that reports errors has to agree on the same spelling.
  def deploy_env_name do
    case env() do
      :prod -> "production"
      :can -> "canary"
      :stag -> "staging"
      :preview -> "preview"
      :dev -> "development"
      :test -> "test"
      other -> Atom.to_string(other)
    end
  end

  def server_version_identifier do
    System.get_env("TUIST_SERVER_VERSION_IDENTIFIER") ||
      if dev?() do
        case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"]) do
          {branch, 0} -> String.trim(branch)
          _ -> nil
        end
      end
  end

  @doc ~S"""
  Returns an list with all the supported environments.
  """
  def all_envs, do: [:dev, :test, :preview, :can, :stag, :prod]

  def blocked_account_handles, do: Application.fetch_env!(:tuist, :blocked_account_handles)

  def blocked_project_handles, do: Application.fetch_env!(:tuist, :blocked_project_handles)

  def test? do
    @compile_env == :test
  end

  def dev? do
    @compile_env == :dev
  end

  def stag? do
    env() == :stag
  end

  def can? do
    env() == :can
  end

  def prod? do
    env() == :prod
  end

  @doc """
  Worktree suffix from `TUIST_DEV_INSTANCE`, set by the mise
  `dev_instance_env.sh` hook. Used to scope ports, DB names, kind
  cluster names, and similar per-worktree resources so multiple
  worktrees can run side by side without colliding. Returns 0 when
  unset (CI, ad-hoc scripts) or when the value isn't a valid integer.
  """
  def dev_instance_suffix do
    case System.get_env("TUIST_DEV_INSTANCE") do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {n, ""} -> n
          _ -> 0
        end

      _ ->
        0
    end
  end

  def truthy?(value) do
    Enum.member?(["1", "true", "TRUE", "yes", "YES"], value)
  end

  @doc """
  Pod role. Controls which subsystems the BEAM brings up at boot:

    * `:web` (default) — full Phoenix endpoint, every Oban queue, every
      ingestion buffer. What the existing server pods run.
    * `:processor` — no Phoenix listener, narrowed Oban queue set to
      `:process_build` and `:process_bazel_tests`. Booted by
      processor-deployment.yaml.
    * `:xcresult_processor` — no Phoenix listener, Oban queue set
      narrowed to `:process_xcresult`. Runs inside a Tart VM on the
      macOS Mac mini fleet (the only place the macOS-only xcresult NIF
      can load). Booted by xcresult-processor-deployment.yaml.
    * `:swift_registry_sync` — no Phoenix listener, Oban queue set
      narrowed to `:swift_registry_sync` + `:swift_registry_release`.
      Consumes jobs enqueued by the `:web` pod's cron, fetches Swift
      packages from GitHub, and writes archives + metadata into the
      registry S3 bucket. The standalone `registry` Phoenix app reads
      back from the same bucket. Booted by
      swift-registry-sync-deployment.yaml. Future ecosystems get
      their own mode (e.g. `:maven_registry_sync`) and Deployment.

  Read once from `TUIST_MODE`. Add new modes here when the supervision tree
  needs another shape (e.g. a future `:scheduler` or `:ingest`).
  """
  def mode, do: mode(System.get_env("TUIST_MODE"))

  @doc """
  Pure variant of `mode/0` that takes the raw `TUIST_MODE` value
  directly. Exposed so callers (tests, future config tooling) can
  exercise the parser without stubbing `System.get_env/1`.
  """
  def mode(nil), do: :web
  def mode(""), do: :web
  def mode("web"), do: :web
  def mode("processor"), do: :processor
  def mode("xcresult_processor"), do: :xcresult_processor
  def mode("swift_registry_sync"), do: :swift_registry_sync

  def mode(other) do
    raise """
    Unknown TUIST_MODE=#{inspect(other)}.
    Expected one of #{inspect(@modes)}, or unset/empty for #{inspect(:web)}.
    """
  end

  def web?, do: mode() == :web

  def processor_mode?, do: mode() == :processor

  def xcresult_processor_mode?, do: mode() == :xcresult_processor

  def swift_registry_sync_mode?, do: mode() == :swift_registry_sync

  def database_url(secrets \\ secrets()) do
    System.get_env("DATABASE_URL") || get([:database_url], secrets)
  end

  def ipv4_database_url(secrets \\ secrets()) do
    System.get_env("TUIST_IPV4_DATABASE_URL") || get([:ipv4_database_url], secrets)
  end

  def database_schema do
    "TUIST_DATABASE_SCHEMA" |> System.get_env() |> database_schema()
  end

  def database_schema(nil), do: @default_database_schema
  def database_schema(""), do: @default_database_schema

  def database_schema(schema) when is_binary(schema) do
    validate_postgres_identifier!(schema, "TUIST_DATABASE_SCHEMA")
  end

  def default_database_schema?(schema \\ database_schema()) do
    schema == @default_database_schema
  end

  def migration_database_url do
    case System.get_env("TUIST_MIGRATION_DATABASE_URL") do
      url when is_binary(url) and url != "" -> url
      _ -> nil
    end
  end

  def database_runtime_role do
    case System.get_env("TUIST_DATABASE_RUNTIME_ROLE") do
      role when is_binary(role) and role != "" -> role
      _ -> nil
    end
  end

  def database_processor_role do
    case System.get_env("TUIST_DATABASE_PROCESSOR_ROLE") do
      role when is_binary(role) and role != "" -> role
      _ -> nil
    end
  end

  def database_swift_registry_sync_role do
    case System.get_env("TUIST_DATABASE_SWIFT_REGISTRY_SYNC_ROLE") do
      role when is_binary(role) and role != "" -> role
      _ -> nil
    end
  end

  @doc """
  Role backing the Grafana Product Usage dashboard. Set only for managed CNPG
  migration Jobs; unset leaves the role's grants untouched.
  """
  def database_grafana_role do
    case System.get_env("TUIST_DATABASE_GRAFANA_ROLE") do
      role when is_binary(role) and role != "" -> role
      _ -> nil
    end
  end

  def database_config_from_url(url) do
    parsed_url = URI.parse(url)

    [username, password] =
      parsed_url.userinfo
      |> String.split(":", parts: 2)
      |> Enum.map(&URI.decode/1)

    [
      database: String.replace_prefix(parsed_url.path, "/", ""),
      username: username,
      password: password,
      hostname: parsed_url.host,
      port: parsed_url.port || 5432
    ]
  end

  def validate_postgres_identifier!(identifier, environment_variable_name) do
    if Regex.match?(@postgres_identifier_regex, identifier) do
      identifier
    else
      raise "#{environment_variable_name} must be a valid unquoted PostgreSQL identifier, " <>
              "got: #{inspect(identifier)}"
    end
  end

  def quote_postgres_identifier(identifier) do
    ~s("#{String.replace(to_string(identifier), "\"", "\"\"")}")
  end

  def network_trusted_report_publishing_enabled?(
        hosted \\ tuist_hosted?(),
        enabled \\ Application.get_env(:tuist, :network_trusted_report_publishing, false)
      ) do
    not hosted and enabled == true
  end

  def network_trusted_cache_access_enabled?(
        hosted \\ tuist_hosted?(),
        enabled \\ Application.get_env(:tuist, :network_trusted_cache_access, false)
      ) do
    not hosted and enabled == true
  end

  def sso_require_login_domain_verification?(
        enabled \\ Application.get_env(:tuist, :sso_require_login_domain_verification, false)
      ) do
    enabled == true
  end

  def tuist_hosted? do
    truthy?(System.get_env("TUIST_CLOUD_HOSTED", "0")) or
      truthy?(System.get_env("TUIST_HOSTED", "0"))
  end

  @doc """
  Whether this deployment offers Tuist Runners, which every account on it can
  use. Every deployment does except self-hosted installations, which have no
  runner fleet.

  This is also the source of truth for co-located private Kura cache
  infrastructure.
  """
  def runners_available?(env \\ env(), hosted \\ tuist_hosted?()) do
    not self_hosted?(env, hosted)
  end

  # A self-hosted server runs as production (or canary) without `TUIST_HOSTED`,
  # which Tuist's managed deployments set. Development, test, staging and
  # preview never run as production or canary.
  defp self_hosted?(env, hosted), do: env in [:can, :prod] and not hosted

  # Enable only after every web/ingestion and build-processor replica accepts the expanded limit.
  # Before a downgrade, disable and drain in-flight reports before rolling back.
  def expanded_build_metadata_enabled? do
    truthy?(System.get_env("TUIST_EXPANDED_BUILD_METADATA_ENABLED", "0"))
  end

  def kura_capacity_admission_required? do
    tuist_hosted?() and truthy?(System.get_env("TUIST_KURA_CAPACITY_ADMISSION_ENABLED", "0"))
  end

  def turnstile_enabled? do
    truthy?(System.get_env("TUIST_TURNSTILE_ENABLED", "0"))
  end

  def turnstile_required? do
    tuist_hosted?() and turnstile_enabled?()
  end

  def turnstile_site_key(secrets \\ secrets()) do
    System.get_env("TUIST_TURNSTILE_SITE_KEY") || get([:turnstile, :site_key], secrets)
  end

  def turnstile_secret_key(secrets \\ secrets()) do
    System.get_env("TUIST_TURNSTILE_SECRET_KEY") || get([:turnstile, :secret_key], secrets)
  end

  @doc """
  Whether the public-page Turnstile challenge is armed on this
  deployment. Read straight off the env at request time so an ops
  flip via `helm upgrade --set env.TUIST_PUBLIC_PAGE_CHALLENGE_ENABLED`
  is picked up without a full restart on the next pod rotation.
  """
  def public_page_challenge_enabled? do
    truthy?(System.get_env("TUIST_PUBLIC_PAGE_CHALLENGE_ENABLED", "0"))
  end

  @doc """
  True when the public-page challenge should be enforced on this
  deployment. Same shape as `turnstile_required?/0`: only the
  tuist-hosted plane is gated so on-premise installs are not
  interfering with their own dashboards.
  """
  def public_page_challenge_required? do
    tuist_hosted?() and public_page_challenge_enabled?()
  end

  @doc """
  How long a solved Turnstile challenge counts as fresh in the
  session, in seconds. Default is four hours so a legitimate anon
  visitor browsing across multiple public projects during a work
  session only sees the interstitial once, while a stale session
  from a shared device still expires within one workday.
  """
  def public_page_challenge_freshness do
    case System.get_env("TUIST_PUBLIC_PAGE_CHALLENGE_FRESHNESS_SECONDS") do
      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {seconds, _} when seconds > 0 -> seconds
          _ -> 4 * 60 * 60
        end

      _ ->
        4 * 60 * 60
    end
  end

  @coverage_retention_defaults %{files: 31, runs: 365}
  @coverage_retention_environment_variables %{
    files: "TUIST_COVERAGE_FILE_RETENTION_DAYS",
    runs: "TUIST_COVERAGE_RUN_RETENTION_DAYS"
  }

  @doc """
  How long coverage rows are kept in ClickHouse, in days: `files` for the
  per-file detail (`coverage_files`, 31 by default) and `runs` for the run
  totals the trend reads (`coverage_runs`, 365 by default). A commit's totals
  and per-file figures (`coverage_commits`, `coverage_file_deltas`) outlive
  the detail. The tables' time-to-live is set from these when
  they are created, or when `mix tuist.coverage.retention` (in a release,
  `Tuist.Release.apply_coverage_retention/0`) re-applies them.
  """
  def coverage_retention_days(environment \\ System.get_env()) when is_map(environment) do
    Map.new(@coverage_retention_defaults, fn {kind, default} ->
      variable = Map.fetch!(@coverage_retention_environment_variables, kind)
      {kind, parse_artifact_retention_days(Map.get(environment, variable), variable) || default}
    end)
  end

  @doc """
  How long a commit's coverage (`coverage_commits`, in PostgreSQL) is kept,
  in days, by when the commit was made: `commits` for the default branch and
  any branch (`TUIST_COVERAGE_COMMIT_RETENTION_DAYS`, three years by default,
  so a project's trend reaches that far back) and `pull_requests` for the
  commits pull requests added (`TUIST_COVERAGE_PULL_REQUEST_COMMIT_RETENTION_DAYS`,
  90 by default).
  """
  def coverage_commit_retention_days(environment \\ System.get_env()) when is_map(environment) do
    for {kind, variable, default} <- [
          {:commits, "TUIST_COVERAGE_COMMIT_RETENTION_DAYS", 1095},
          {:pull_requests, "TUIST_COVERAGE_PULL_REQUEST_COMMIT_RETENTION_DAYS", 90}
        ],
        into: %{} do
      {kind, parse_artifact_retention_days(Map.get(environment, variable), variable) || default}
    end
  end

  @doc """
  The size, in bytes, of a run's coverage above which a client that processed
  the result bundle itself uploads the coverage to object storage instead of
  sending it inline with the run. Set with
  `TUIST_COVERAGE_INLINE_THRESHOLD_BYTES`; 500 KB by default. The request body
  limit the inline form is held to applies after a compressed body is
  inflated, and coverage compresses tenfold to fiftyfold, so the default stays
  under it however a client measures the coverage: the Xcode CLI compares the
  uncompressed size, while older Xcode CLIs, Mix and Gradle compare the
  compressed size.
  """
  def coverage_inline_threshold_bytes(environment \\ System.get_env()) when is_map(environment) do
    case Map.get(environment, "TUIST_COVERAGE_INLINE_THRESHOLD_BYTES") do
      nil -> 500_000
      value -> parse_artifact_retention_days(value, "TUIST_COVERAGE_INLINE_THRESHOLD_BYTES") || 500_000
    end
  end

  @doc """
  The most bytes an uploaded coverage report may inflate to before its
  publication is cancelled, from `TUIST_COVERAGE_MAX_INFLATED_BYTES`; 2 GB by
  default. DEFLATE expands up to about 1000:1, so without a ceiling a small
  upload could fill the disk it is inflated to. A quarter of it bounds the
  compressed upload, which is refused before it is downloaded
  (`Tuist.Tests.Workers.PublishCoverageWorker.download/4`).
  """
  def coverage_max_inflated_bytes(environment \\ System.get_env()) when is_map(environment) do
    parse_artifact_retention_days(
      Map.get(environment, "TUIST_COVERAGE_MAX_INFLATED_BYTES"),
      "TUIST_COVERAGE_MAX_INFLATED_BYTES"
    ) ||
      2_000_000_000
  end

  @git_history_environment_variables %{
    window_days: "TUIST_GIT_HISTORY_WINDOW_DAYS",
    window_commits: "TUIST_GIT_HISTORY_WINDOW_COMMITS",
    deepen_budget_seconds: "TUIST_GIT_HISTORY_DEEPEN_BUDGET_SECONDS",
    upload_batch_size: "TUIST_GIT_HISTORY_UPLOAD_BATCH_SIZE",
    commit_file_limit: "TUIST_GIT_HISTORY_COMMIT_FILE_LIMIT"
  }

  @doc """
  The server-wide Git history settings set through the environment, as a map
  of the keys `Tuist.GitHistory.settings/1` merges over its defaults. Only the
  variables that are set appear, each a positive integer.
  """
  def git_history_defaults(environment \\ System.get_env()) when is_map(environment) do
    Enum.reduce(@git_history_environment_variables, %{}, fn {key, variable}, acc ->
      case parse_artifact_retention_days(Map.get(environment, variable), variable) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  def artifact_retention_days(environment \\ System.get_env()) when is_map(environment) do
    Enum.reduce(@artifact_retention_environment_variables, %{}, fn {resource_type, environment_variable}, acc ->
      case parse_artifact_retention_days(Map.get(environment, environment_variable), environment_variable) do
        nil -> acc
        days -> Map.put(acc, resource_type, days)
      end
    end)
  end

  defp parse_artifact_retention_days(nil, _environment_variable), do: nil

  defp parse_artifact_retention_days(value, environment_variable) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      _ when value == "" -> nil
      {days, ""} when days > 0 -> days
      _ -> raise_invalid_artifact_retention_days(environment_variable, value)
    end
  end

  defp parse_artifact_retention_days(value, environment_variable) do
    raise_invalid_artifact_retention_days(environment_variable, value)
  end

  defp raise_invalid_artifact_retention_days(environment_variable, value) do
    raise "#{environment_variable} must be a positive integer number of days, got: #{inspect(value)}"
  end

  def test_user_login_enabled? do
    dev?() or truthy?(System.get_env("TUIST_TEST_USER_LOGIN_ENABLED", "0"))
  end

  def dev_all_locales?, do: @dev_all_locales

  # Both :dev and :test compile a single locale ("en") by default so Gettext
  # doesn't generate all locale modules on every cold compile. Tests that
  # genuinely exercise other locales are tagged `:locale` and only run when
  # TUIST_DEV_ALL_LOCALES=1 flips this back to the full set.
  def single_locale?, do: (dev?() or test?()) and not dev_all_locales?()

  def log_level do
    "TUIST_LOG_LEVEL" |> System.get_env("info") |> String.to_atom()
  end

  def use_ssl_for_database? do
    truthy?(System.get_env("TUIST_USE_SSL_FOR_DATABASE", "1"))
  end

  # Verification is opt-in so upgrades keep connecting to databases whose
  # certificates chain to a private CA (RDS, Cloud SQL, self-managed).
  # Postgrex verifies the peer and hostname by default for `true` and keyword
  # lists, and sets SNI from the host of each connection, so neither is pinned
  # here. `true` also defers loading the OS trust store to connect time.
  def database_ssl_options do
    ca_cert_file = System.get_env("TUIST_DATABASE_SSL_CA_CERT_FILE")

    cond do
      not truthy?(System.get_env("TUIST_DATABASE_SSL_VERIFY", "0")) -> [verify: :verify_none]
      ca_cert_file in [nil, ""] -> true
      true -> [cacertfile: validate_database_ca_cert_file!(ca_cert_file)]
    end
  end

  defp validate_database_ca_cert_file!(path) do
    with {:ok, pem} <- File.read(path),
         true <- Enum.any?(:public_key.pem_decode(pem), &match?({:Certificate, _, _}, &1)) do
      path
    else
      _ ->
        raise "TUIST_DATABASE_SSL_CA_CERT_FILE must point to a readable PEM file with CA certificates, got: #{inspect(path)}"
    end
  end

  def dev_use_remote_storage? do
    not dev?() or truthy?(System.get_env("TUIST_DEV_USE_REMOTE_STORAGE", "0"))
  end

  def kura_lvm_region_ids do
    "TUIST_KURA_LVM_REGIONS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def kura_thin_region_ids do
    "TUIST_KURA_THIN_REGIONS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def kura_thin_enrolled_region_ids do
    "TUIST_KURA_THIN_ENROLLED_REGIONS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def kura_available_region_ids do
    "TUIST_KURA_AVAILABLE_REGIONS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def kura_runtime_image_tag(secrets \\ secrets()) do
    System.get_env("TUIST_KURA_RUNTIME_IMAGE_TAG") || get([:kura, :runtime_image_tag], secrets)
  end

  @doc """
  Whether this process is the deployment that owns the Kura control
  plane. Booting in web mode is not proof: an ops eval Job boots the
  application with the server's envFrom secrets but not its manifest env
  list, and its reconcile would read the secrets-blob runtime-tag
  fallback (a stale blob tag superseded a live rollout on staging that
  way). The helm-injected env var is the discriminator that fails safe:
  only the server Deployment's manifest carries it.
  """
  def kura_control_plane? do
    case System.get_env("TUIST_KURA_RUNTIME_IMAGE_TAG") do
      tag when is_binary(tag) and tag != "" -> true
      _ -> false
    end
  end

  @doc """
  Account handles of the Tuist-owned accounts that make up wave 0 (the
  canary) of a progressive Kura runtime rollout. Comma-separated in
  `TUIST_KURA_CANARY_ACCOUNT_HANDLES`; matching is case-insensitive.
  """
  def kura_canary_account_handles do
    "TUIST_KURA_CANARY_ACCOUNT_HANDLES"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Per-environment override of the rollout pacing default ("progressive"
  or "expedited"). Unset, production paces progressively and every other
  environment fans out expedited. Exists for the staging drills that
  exercise progressive mode through real releases before production
  enablement (spec #79 rollout plan).
  """
  def kura_rollout_pacing do
    case System.get_env("TUIST_KURA_ROLLOUT_PACING") do
      value when value in ["progressive", "expedited"] -> value
      _ -> nil
    end
  end

  @doc """
  Image tag the deploy explicitly asked to expedite (the deployment-input
  form of the expedite verb, used for rollbacks to a proven tag). Only a
  rollout created for exactly this tag starts expedited, so the value
  cannot leak onto a later unrelated rollout.
  """
  def kura_rollout_expedite_tag do
    case System.get_env("TUIST_KURA_ROLLOUT_EXPEDITE_TAG") do
      nil -> nil
      value -> with "" <- String.trim(value), do: nil
    end
  end

  @doc """
  Webhook URL for best-effort internal ops notifications (Kura rollout
  lifecycle). Context only — Grafana owns paging — so an unset value
  disables the notifications rather than failing anything.
  """
  def ops_slack_webhook_url(secrets \\ secrets()) do
    System.get_env("TUIST_OPS_SLACK_WEBHOOK_URL") || get([:ops, :slack_webhook_url], secrets)
  end

  @doc """
  The public peer failover IP for a bare-metal region, or `nil` when none is
  configured. Self-hosted nodes resolve a region's `peer.` host to this IP; the
  CAPI provider keeps it routed to a healthy box of the region's pool. Read from
  `TUIST_KURA_PEER_FAILOVER_IPS` as a `region=ip` comma list (e.g.
  `eu-west=1.2.3.4,ca-east=5.6.7.8`).
  """
  def kura_peer_failover_ip(region_id) when is_binary(region_id) do
    "TUIST_KURA_PEER_FAILOVER_IPS"
    |> System.get_env("")
    |> String.split(",", trim: true)
    |> Enum.find_value(fn pair ->
      case pair |> String.split("=", parts: 2) |> Enum.map(&String.trim/1) do
        [key, ip] when key == region_id and ip != "" -> ip
        _ -> nil
      end
    end)
  end

  def kura_tuist_base_url do
    System.get_env("TUIST_KURA_TUIST_BASE_URL")
  end

  @doc "The public gRPC endpoint of the remote execution gateways, such as `grpcs://execution.tuist.dev`."
  def remote_execution_endpoint do
    System.get_env("TUIST_REMOTE_EXECUTION_ENDPOINT")
  end

  @doc """
  The placement apply budgets an operator has written, as counts keyed by the
  name of the proposal kind they were written for.

  Empty unless `TUIST_KURA_PLACEMENT_AUTOMATIC_APPLIES_PER_DAY` names a kind,
  so placement proposes and an operator applies until someone decides
  otherwise. A placement transition costs a region's worth of cache refill,
  which is why this starts stopped where claim sizing does not.

  Per kind because only one kind needs a fleet-wide ceiling at all. Every rung
  already limits how often a single account may move: expansion stops at the
  plan's region count, relocation runs once a quarter, correction fires once in
  an account's life. Those bound the thing worth bounding and they scale with
  the fleet by construction. A count here bounds something different, which is
  how much of the *whole fleet* may move in a day, and the only reason to want
  that is a rung deciding wrongly for everyone at once. Retirement is where
  that matters, because it deletes volumes an hour later with no cancel; the
  others cost a cold cache and re-derive their own decision.

  The format is `kind=count` pairs, such as `expand=all,relocate=all,retire=25`.
  A count of `all` lifts the fleet-wide ceiling on that kind entirely, which is
  the right setting for every kind whose mistake is recoverable: the rungs
  already limit how often any one account may move, and a fleet-wide constant
  in front of a queue that grows with the account count is a ceiling that stops
  tracking the fleet the moment it grows.

  Which names are real kinds is
  `Tuist.Kura.PlacementProposals.automatic_apply_budgets/0`'s to decide. What
  is settled here is only that an unreadable pair is dropped rather than
  failing the boot: a typo in one entry must not be able to take the server
  down, and the direction it fails in is the one that applies nothing.
  """
  def kura_placement_automatic_applies_per_day(environment \\ System.get_env()) when is_map(environment) do
    environment
    |> Map.get("TUIST_KURA_PLACEMENT_AUTOMATIC_APPLIES_PER_DAY")
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.reduce(%{}, &put_placement_budget/2)
  end

  defp put_placement_budget(pair, budgets) do
    with [name, count] <- String.split(pair, "=", parts: 2),
         {:ok, count} <- parse_placement_budget(String.trim(count)) do
      Map.put(budgets, String.trim(name), count)
    else
      _ -> budgets
    end
  end

  defp parse_placement_budget("all"), do: {:ok, :unlimited}

  defp parse_placement_budget(count) do
    case Integer.parse(count) do
      {count, ""} when count >= 0 -> {:ok, count}
      _ -> :error
    end
  end

  @doc """
  Days without cache demand before a Kura instance is drained and reclaimed,
  and the shortened window Air may use under capacity pressure.

  Defaults are the spec's 90 and 60. They are configurable because otherwise
  the archival half of the lifecycle cannot be exercised in any environment
  without waiting a quarter: its first real run would be in production against
  customer instances. Staging runs short windows so every deploy re-validates
  the whole cycle.

  Read from `TUIST_KURA_INACTIVE_DAYS` and
  `TUIST_KURA_PRESSURE_INACTIVE_DAYS`.
  """
  def kura_inactive_days, do: positive_env_integer("TUIST_KURA_INACTIVE_DAYS", 90)

  def kura_pressure_inactive_days, do: positive_env_integer("TUIST_KURA_PRESSURE_INACTIVE_DAYS", 60)

  @doc """
  Days without cache demand before an Air Kura instance is drained and
  reclaimed. Demand is real cache traffic (activation requests and the usage
  managed nodes report), so an Air account that used its cache for a while and
  stopped gives the room back within a week, and gets it back on its next cache
  request.

  Read from `TUIST_KURA_AIR_INACTIVE_DAYS`.
  """
  def kura_air_inactive_days, do: positive_env_integer("TUIST_KURA_AIR_INACTIVE_DAYS", 7)

  @doc """
  Days a Pro Kura instance may stay in service without storing anything before it
  is drained and reclaimed, measured from when it entered service.

  Read from `TUIST_KURA_UNUSED_DAYS`.
  """
  def kura_unused_days, do: positive_env_integer("TUIST_KURA_UNUSED_DAYS", 7)

  @doc """
  Hours an Air instance may stay in service without storing anything before
  it is reclaimed. Its unused-instance tracking grace is capped at this window;
  sufficient storage telemetry is still required.

  Read from `TUIST_KURA_AIR_UNUSED_HOURS`.
  """
  def kura_air_unused_hours, do: positive_env_integer("TUIST_KURA_AIR_UNUSED_HOURS", 24)

  @doc """
  Days an account-region's demand must have been tracked before inactivity
  archival, however old the recorded demand looks. For never-used Air instances,
  this grace is capped at `kura_air_unused_hours/0`.

  This is what makes enabling archival against freshly backfilled data safe, so
  it defaults to a week. Staging sets it to zero, where the backfill is not the
  concern and waiting a week to exercise archival would defeat the point.

  Read from `TUIST_KURA_DEMAND_TRACKING_GRACE_DAYS`.
  """
  def kura_demand_tracking_grace_days do
    case System.get_env("TUIST_KURA_DEMAND_TRACKING_GRACE_DAYS") do
      nil -> 7
      value -> parse_non_negative_days!("TUIST_KURA_DEMAND_TRACKING_GRACE_DAYS", value)
    end
  end

  defp positive_env_integer(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case parse_non_negative_days!(name, value) do
          0 -> raise ArgumentError, "#{name} must be greater than 0"
          days -> days
        end
    end
  end

  # An unreadable window must not silently fall back to the default: a typo
  # would leave an operator believing they had shortened or lengthened it.
  defp parse_non_negative_days!(name, value) do
    case Integer.parse(String.trim(value)) do
      {days, ""} when days >= 0 ->
        days

      _ ->
        raise ArgumentError, "#{name} must be a non-negative integer number of days, got: #{inspect(value)}"
    end
  end

  @doc """
  Cron schedule for the Kura archival sweep, which decides that an instance
  has gone a full inactive window without cache demand.

  Hourly by default so an unused Air instance is considered within an hour of
  its eligibility window, rather than waiting until midnight.
  Deployments can override the cadence to match their lifecycle windows.

  Read from `TUIST_KURA_ARCHIVAL_SWEEP_CRON`.
  """
  def kura_archival_sweep_cron do
    case System.get_env("TUIST_KURA_ARCHIVAL_SWEEP_CRON") do
      nil -> "@hourly"
      "" -> "@hourly"
      schedule -> String.trim(schedule)
    end
  end

  @doc """
  Whether Kura cache-demand records bypass the in-memory buffer and are
  written straight through the caller's repo connection.

  False in every deployed environment: buffering is what keeps the demand hook
  off the database on the cache-endpoint hot path. Tests turn it on so a
  process-wide buffer cannot carry one test's demand into another's
  transaction, the same way `Tuist.Ingestion.Bufferable` does.
  """
  def kura_demand_write_through_repo? do
    :tuist
    |> Application.get_env(Tuist.Kura.Demand, [])
    |> Keyword.get(:write_through_repo, false)
  end

  def prometheus_enabled? do
    prometheus_enabled = System.get_env("TUIST_PROMETHEUS_ENABLED")

    if is_nil(prometheus_enabled) do
      not dev?() and not test?()
    else
      truthy?(prometheus_enabled)
    end
  end

  def license_key(secrets \\ secrets()) do
    System.get_env("TUIST_LICENSE_KEY") || get([:license], secrets) ||
      get([:license, :key], secrets)
  end

  def license_certificate_base64(secrets \\ secrets()) do
    System.get_env("TUIST_LICENSE_CERTIFICATE_BASE64") ||
      get([:license, :certificate, :base64], secrets)
  end

  def license_verify_key(secrets \\ secrets()) do
    System.get_env("TUIST_LICENSE_VERIFY_KEY") || get([:license, :verify_key], secrets)
  end

  def use_ipv6?(secrets \\ secrets()) do
    get([:use_ipv6], secrets)
  end

  def redis_conn_name do
    :redis
  end

  def redis_url(secrets \\ secrets()) do
    get([:redis_url], secrets)
  end

  def agent_auth_default_trusted_providers, do: @agent_auth_default_trusted_providers

  def agent_auth_trusted_providers(secrets \\ secrets()) do
    case System.get_env("TUIST_AGENT_AUTH_TRUSTED_PROVIDERS_JSON") ||
           get([:agent_auth, :trusted_providers], secrets) do
      providers when is_list(providers) ->
        providers

      providers_json when is_binary(providers_json) and providers_json != "" ->
        case JSON.decode(providers_json) do
          {:ok, providers} when is_list(providers) -> providers
          _ -> []
        end

      _ ->
        agent_auth_default_trusted_providers()
    end
  end

  def cache_endpoints(secrets \\ secrets()) do
    case get([:cache, :endpoints], secrets) do
      endpoints when is_binary(endpoints) ->
        split_endpoints(endpoints)

      _ ->
        nil
    end
  end

  def kura_endpoints(secrets \\ secrets(), env_value \\ System.get_env("TUIST_KURA_ENDPOINTS")) do
    case endpoint_env_value(env_value) || get([:kura, :endpoints], secrets) do
      endpoints when is_binary(endpoints) ->
        split_endpoints(endpoints)

      _ ->
        nil
    end
  end

  def database_pool_size(secrets \\ secrets()) do
    case get([:database, :pool_size], secrets) do
      pool_size when is_binary(pool_size) -> String.to_integer(pool_size)
      _ -> 10
    end
  end

  def database_queue_target(secrets \\ secrets()) do
    case get([:database, :queue_target], secrets) do
      queue_target when is_binary(queue_target) -> String.to_integer(queue_target)
      _ -> 200
    end
  end

  def database_queue_interval(secrets \\ secrets()) do
    case get([:database, :queue_interval], secrets) do
      queue_interval when is_binary(queue_interval) -> String.to_integer(queue_interval)
      _ -> 2000
    end
  end

  def analytics_enabled?(secrets \\ secrets()) do
    not is_nil(faro_collector_url(secrets))
  end

  def error_tracking_enabled? do
    truthy?(System.get_env("TUIST_FORCE_ERROR_TRACKING")) ||
      (tuist_hosted?() and Enum.member?([:prod, :stag, :can], env()))
  end

  def version do
    case System.get_env("TUIST_VERSION") do
      nil -> to_string(Application.spec(:tuist)[:vsn])
      "" -> to_string(Application.spec(:tuist)[:vsn])
      version -> version
    end
  end

  @doc """
  Email domain whose confirmed members are Tuist operators. Used only
  as a routing heuristic (redirect a non-member operator to the ops
  reason form vs. 404 a regular customer); the real gates are
  ops.tuist.dev's Pomerium/Google-OIDC and the offline grant
  verification. Defaults to `tuist.dev`.
  """
  def operator_email_domain(secrets \\ secrets()) do
    [:operator_email_domain] |> get(secrets, default_value: "tuist.dev") |> String.trim() |> String.downcase()
  end

  @doc """
  Handles of the organizations Tuist itself owns, such as `tuist`. Their
  members, whatever their email domain, are workforce for the dormant-account
  sweep (`Tuist.Accounts.Dormancy`). Comma-separated in
  `TUIST_INTERNAL_ORGANIZATION_HANDLES`; matched case-insensitively. Empty by
  default, so self-hosted instances, where a `tuist` handle can belong to
  anyone, are not affected.
  """
  def internal_organization_handles(secrets \\ secrets()) do
    case get([:internal_organization_handles], secrets) do
      handles when is_binary(handles) ->
        handles
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  @doc "Whether the operator email domain is set explicitly instead of using the `tuist.dev` default."
  def operator_email_domain_configured?(secrets \\ secrets()) do
    case get([:operator_email_domain], secrets) do
      domain when is_binary(domain) -> String.trim(domain) != ""
      _ -> false
    end
  end

  @doc """
  Configured immutable shard target IDs. Each store release publishes its own
  map, so the runner-local and public stores arrive in separate variables. A
  malformed map contributes no targets.
  """
  def shard_storage_targets do
    for name <- ["TUIST_SHARD_STORAGE_TARGETS", "TUIST_PUBLIC_SHARD_STORAGE_TARGETS"],
        {:ok, targets} when is_map(targets) <- [JSON.decode(System.get_env(name) || "{}")],
        reduce: %{} do
      acc -> Map.merge(targets, acc)
    end
  end

  @doc """
  PEM-encoded Ed25519 PUBLIC key used to verify operator access grant
  tokens minted by ops.tuist.dev. nil when unset, in which case grant
  verification fails closed (no operator grants are honoured).
  """
  def operator_grant_public_key(secrets \\ secrets()) do
    get([:operator_grant, :public_key], secrets)
  end

  @doc """
  The `aud` claim required on operator grant tokens. Pinned per
  environment so a token minted for a different env can't be replayed.
  Must match ops.tuist.dev's `OPERATOR_GRANT_AUDIENCE`.
  """
  def operator_grant_audience(secrets \\ secrets()) do
    get([:operator_grant, :audience], secrets, default_value: "tuist-server")
  end

  @doc """
  Maximum allowed lifetime (`exp - iat`, seconds) of an operator grant
  token. A token claiming a longer lifetime is rejected, so a
  compromised signer can't mint a long-lived grant. Defaults to 1h.
  """
  def operator_grant_max_ttl_seconds(secrets \\ secrets()) do
    case get([:operator_grant, :max_ttl_seconds], secrets, default_value: 3600) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  @doc """
  Base URL of the ops.tuist.dev reason form a non-member operator is
  redirected to before they can access a customer project. nil by
  default: the redirect is opt-in per environment and stays off until
  ops.tuist.dev is Pomerium-fronted and routes `/grants` with a
  matching audience. Offline grant verification does not depend on this.
  """
  def ops_reason_form_url(secrets \\ secrets()) do
    get([:ops, :reason_form_url], secrets, default_value: nil)
  end

  @doc """
  PEM-encoded Ed25519 PRIVATE key the server uses to sign per-account
  cache-signing grants delivered to runner jobs. The runner's
  Tuist EE CLI verifies the grant OFFLINE with the matching public half
  baked into the binary, then scopes cached-artifact signatures to the
  account instead of the machine MAC so a warm cache volume's binaries
  validate as local hits across VMs. nil (default) disables grant minting:
  dispatch omits the grant, the CLI falls back to the MAC default, and the
  manifest/helper cache warmth still applies — the volume just re-pulls its
  binaries, exactly as without the EE change. Provisioned per environment
  from 1Password via ESO; distinct from the artifact-signing key.
  """
  def cache_grant_private_key(secrets \\ secrets()) do
    System.get_env("TUIST_CACHE_GRANT_PRIVATE_KEY") || get([:cache_grant, :private_key], secrets)
  end

  @doc """
  The `aud` claim stamped on cache-signing grants, pinned per environment
  so a grant minted for one env can't be replayed in another. Must match
  the audience the EE CLI enforces.
  """
  def cache_grant_audience(secrets \\ secrets()) do
    get([:cache_grant, :audience], secrets, default_value: "tuist-runner-cache")
  end

  @doc """
  Lifetime (seconds) of a cache-signing grant. Set to the job's maximum
  lifetime plus a small margin: a leaked grant (runner jobs run arbitrary
  user code that can read the environment) expires within the job's TTL,
  so sustaining cross-machine reuse would require continuously harvesting
  fresh grants from one's own live runner jobs — an authorized account
  member who can already download the same artifacts with their account
  token. Defaults to 7h (GitHub Actions' 6h job ceiling + margin).
  """
  def cache_grant_ttl_seconds(secrets \\ secrets()) do
    case get([:cache_grant, :ttl_seconds], secrets, default_value: 25_200) do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
    end
  end

  def faro_collector_url(secrets \\ secrets()) do
    System.get_env("TUIST_FARO_COLLECTOR_URL") || get([:faro, :collector_url], secrets)
  end

  def faro_receiver_url do
    System.get_env("TUIST_FARO_RECEIVER_URL")
  end

  def object_storage_provider(secrets \\ secrets()) do
    provider =
      System.get_env("TUIST_OBJECT_STORAGE_PROVIDER") ||
        get([:object_storage, :provider], secrets) ||
        "s3"

    case provider do
      "s3" -> :s3
      :s3 -> :s3
      "azure_blob" -> :azure_blob
      :azure_blob -> :azure_blob
      other -> raise "Unsupported TUIST_OBJECT_STORAGE_PROVIDER=#{inspect(other)}. Expected \"s3\" or \"azure_blob\"."
    end
  end

  def azure_storage_account_name(secrets \\ secrets()) do
    System.get_env("TUIST_AZURE_STORAGE_ACCOUNT_NAME") ||
      get([:azure_blob, :account_name], secrets)
  end

  def azure_storage_account_key(secrets \\ secrets()) do
    System.get_env("TUIST_AZURE_STORAGE_ACCOUNT_KEY") ||
      get([:azure_blob, :account_key], secrets)
  end

  def azure_blob_container_name(secrets \\ secrets()) do
    System.get_env("TUIST_AZURE_BLOB_CONTAINER_NAME") ||
      get([:azure_blob, :container_name], secrets)
  end

  def azure_blob_endpoint(secrets \\ secrets()) do
    System.get_env("TUIST_AZURE_BLOB_ENDPOINT") ||
      get([:azure_blob, :endpoint], secrets) ||
      azure_blob_endpoint_from_account_name(azure_storage_account_name(secrets))
  end

  def azure_blob_service_version(secrets \\ secrets()) do
    System.get_env("TUIST_AZURE_BLOB_SERVICE_VERSION") ||
      get([:azure_blob, :service_version], secrets) ||
      "2020-12-06"
  end

  defp azure_blob_endpoint_from_account_name(nil), do: nil
  defp azure_blob_endpoint_from_account_name(""), do: nil
  defp azure_blob_endpoint_from_account_name(account_name), do: "https://#{account_name}.blob.core.windows.net"

  def s3_authentication_method(secrets \\ secrets()) do
    case get([:s3, :authentication_method], secrets) do
      authentication_method when is_binary(authentication_method) ->
        String.to_atom(authentication_method)

      _ ->
        :env_access_key_id_and_secret_access_key
    end
  end

  def s3_connect_timeout(secrets \\ secrets()) do
    case get([:s3, :connect_timeout], secrets) do
      "infinity" ->
        :infinity

      connect_timeout when is_binary(connect_timeout) ->
        to_timeout(second: String.to_integer(connect_timeout))

      _ ->
        # Standard timeout for establishing connections
        to_timeout(second: 10)
    end
  end

  def s3_receive_timeout(secrets \\ secrets()) do
    case get([:s3, :receive_timeout], secrets) do
      "infinity" ->
        :infinity

      receive_timeout when is_binary(receive_timeout) ->
        to_timeout(second: String.to_integer(receive_timeout))

      _ ->
        # Generous receive timeout for large file downloads
        to_timeout(minute: 1)
    end
  end

  def s3_pool_timeout(secrets \\ secrets()) do
    case get([:s3, :pool_timeout], secrets) do
      "infinity" ->
        :infinity

      pool_timeout when is_binary(pool_timeout) ->
        to_timeout(second: String.to_integer(pool_timeout))

      _ ->
        # Standard pool timeout
        to_timeout(second: 5)
    end
  end

  def s3_pool_max_idle_time(secrets \\ secrets()) do
    case get([:s3, :pool_max_idle_time], secrets) do
      "infinity" ->
        :infinity

      pool_max_idle_time when is_binary(pool_max_idle_time) ->
        to_timeout(second: String.to_integer(pool_max_idle_time))

      _ ->
        # Keep the connections alive for reusability
        :infinity
    end
  end

  def s3_pool_size(secrets \\ secrets()) do
    case get([:s3, :pool_size], secrets) do
      pool_size when is_binary(pool_size) -> String.to_integer(pool_size)
      # Since we use http2, which allows multi-plexing, the size of the pool can be smaller
      _ -> 500
    end
  end

  def s3_pool_count(secrets \\ secrets()) do
    case get([:s3, :pool_count], secrets) do
      pool_count when is_binary(pool_count) -> String.to_integer(pool_count)
      _ -> System.schedulers_online()
    end
  end

  def s3_protocols(secrets \\ secrets()) do
    case get([:s3, :protocol], secrets) do
      protocol when is_binary(protocol) -> [String.to_atom(protocol)]
      _ -> [:http1]
    end
  end

  def s3_access_key_id(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_ACCESS_KEY_ID") ||
        System.get_env("AWS_ACCESS_KEY_ID") ||
        get([:s3, :access_key_id], secrets)
    else
      "minio"
    end
  end

  def s3_secret_access_key(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_SECRET_ACCESS_KEY") ||
        System.get_env("AWS_SECRET_ACCESS_KEY") ||
        get([:s3, :secret_access_key], secrets)
    else
      "minio1234"
    end
  end

  def s3_region(secrets \\ secrets()) do
    System.get_env("TUIST_S3_REGION") ||
      System.get_env("AWS_REGION") ||
      get([:s3, :region], secrets) ||
      "auto"
  end

  def s3_bucket_name(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_BUCKET_NAME") || get([:s3, :bucket_name], secrets)
    else
      "tuist-development"
    end
  end

  def cache_s3_bucket_name(secrets \\ secrets()) do
    System.get_env("TUIST_CACHE_S3_BUCKET_NAME") ||
      System.get_env("S3_BUCKET") ||
      get([:cache, :s3, :bucket], secrets)
  end

  def cache_xcode_s3_bucket_name(secrets \\ secrets()) do
    System.get_env("TUIST_CACHE_XCODE_S3_BUCKET_NAME") ||
      System.get_env("S3_XCODE_CACHE_BUCKET") ||
      get([:cache, :s3, :xcode_cache_bucket], secrets) ||
      cache_s3_bucket_name(secrets)
  end

  def s3_endpoint(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      System.get_env("TUIST_S3_ENDPOINT") || get([:s3, :endpoint], secrets)
    else
      System.get_env("TUIST_LOCAL_S3_ENDPOINT") ||
        case System.get_env("TUIST_MINIO_API_PORT") do
          port when is_binary(port) -> "http://localhost:#{port}"
          _ -> get([:local_s3_endpoint], secrets) || "http://localhost:9095"
        end
    end
  end

  def s3_virtual_host(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      case System.get_env("TUIST_S3_VIRTUAL_HOST") do
        nil -> [:s3, :virtual_host] |> get(secrets) |> truthy?()
        value -> truthy?(value)
      end
    else
      false
    end
  end

  def s3_bucket_as_host(secrets \\ secrets()) do
    if dev_use_remote_storage?() do
      case System.get_env("TUIST_S3_BUCKET_AS_HOST") do
        nil -> [:s3, :bucket_as_host] |> get(secrets) |> truthy?()
        value -> truthy?(value)
      end
    else
      false
    end
  end

  def s3_ca_cert_pem(secrets \\ secrets()) do
    System.get_env("TUIST_S3_CA_CERT_PEM") || get([:s3, :ca_cert_pem], secrets)
  end

  def slack_tuist_token(secrets \\ secrets()) do
    get([:slack, :tuist, :token], secrets)
  end

  def slack_client_id(secrets \\ secrets()) do
    get([:slack, :client_id], secrets)
  end

  def slack_client_secret(secrets \\ secrets()) do
    get([:slack, :client_secret], secrets)
  end

  def slack_configured?(secrets \\ secrets()) do
    slack_client_id(secrets) != nil and slack_client_secret(secrets) != nil
  end

  def stripe_api_key(secrets \\ secrets()) do
    get([:stripe, :secret_key], secrets)
  end

  def stripe_publishable_key(secrets \\ secrets()) do
    get([:stripe, :publishable_key], secrets)
  end

  def stripe_endpoint_secret(secrets \\ secrets()) do
    get([:stripe, :endpoint_secret], secrets)
  end

  def stripe_configured?(secrets \\ secrets()) do
    stripe_api_key(secrets) != nil and stripe_publishable_key(secrets) != nil and
      stripe_endpoint_secret(secrets) != nil
  end

  def stripe_prices(secrets \\ secrets()) do
    case get([:stripe, :prices], secrets) do
      # TUIST_STRIPE_PRICES carries the plan -> category -> [price ids] map and
      # the top-level runner meter event name -> price id map as a JSON string
      # (rendered by the chart / set in mise for dev). A raw map is only seen in
      # tests that stub it directly.
      prices when is_map(prices) -> prices
      prices when is_binary(prices) -> JSON.decode!(prices)
      _ -> nil
    end
  end

  def minio_console_port(secrets \\ secrets()) do
    case System.get_env("TUIST_MINIO_CONSOLE_PORT") do
      port when is_binary(port) -> String.to_integer(port)
      _ -> get([:minio, :console_port], secrets, default_value: 9098)
    end
  end

  def atlas_email_api_key(secrets \\ secrets()) do
    get([:atlas, :email_api_key], secrets)
  end

  def github_token_update_package_releases(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES") ||
      get([:github, :token, :update_package_releases], secrets)
  end

  def github_app_name(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_NAME") || get([:github, :app_name], secrets)
  end

  def github_app_id(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_ID") || get([:github, :app_id], secrets)
  end

  def github_app_client_id(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_CLIENT_ID") ||
      get([:github, :app_client_id], secrets) || get([:github, :oauth_id], secrets)
  end

  def github_app_client_secret(secrets \\ secrets()) do
    System.get_env("TUIST_GITHUB_APP_CLIENT_SECRET") ||
      get([:github, :app_client_secret], secrets) || get([:github, :oauth_secret], secrets)
  end

  def github_app_private_key(secrets \\ secrets()) do
    base_64_key =
      System.get_env("TUIST_GITHUB_APP_PRIVATE_KEY_BASE64") ||
        get([:github, :app_private_key_base64], secrets)

    cond do
      is_binary(base_64_key) -> Base.decode64!(base_64_key)
      env_key = System.get_env("TUIST_GITHUB_APP_PRIVATE_KEY") -> env_key
      true -> get([:github, :app_private_key], secrets)
    end
  end

  de