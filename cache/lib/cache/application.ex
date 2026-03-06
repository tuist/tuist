defmodule Cache.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    if System.get_env("SKIP_MIGRATIONS") != "true" do
      migrate()
    end

    check_sqlite_health()

    if Cache.Config.analytics_enabled?() do
      Cache.Telemetry.attach()
    end

    Oban.Telemetry.attach_default_logger()
    start_sentry_logger()
    start_loki_logger()
    start_opentelemetry()

    base_children = [
      Cache.Repo,
      Cache.KeyValueBuffer,
      Cache.CacheArtifactsBuffer,
      Cache.S3TransfersBuffer,
      {Phoenix.PubSub, name: Cache.PubSub},
      Cache.Authentication,
      Cache.S3,
      Cache.KeyValueStore,
      Cache.MultipartUploads,
      Cache.Registry.Metadata,
      CacheWeb.Endpoint,
      Cache.SocketLinker,
      # Cannot alias Cache.Finch to Finch or it'll conflict with the top-level library
      # credo:disable-for-next-line Credo.Check.Design.AliasUsage
      {Finch, name: Cache.Finch, pools: Cache.Finch.Pools.config()},
      Cache.PromEx,
      {Oban, Application.get_env(:cache, Oban)}
    ]

    children =
      if Cache.Config.analytics_enabled?() do
        base_children ++
          [Cache.CASEventsPipeline, Cache.GradleCacheEventsPipeline, Cache.RegistryDownloadEventsPipeline]
      else
        base_children
      end

    opts = [strategy: :one_for_one, name: Cache.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp migrate do
    repos = Application.fetch_env!(:cache, :ecto_repos)

    for repo <- repos do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp check_sqlite_health do
    repos = Application.fetch_env!(:cache, :ecto_repos)

    for repo <- repos do
      Ecto.Migrator.with_repo(repo, fn _repo ->
        log_sqlite_health()
      end)
    end
  end

  defp log_sqlite_health do
    with {:ok, %{rows: [[auto_vacuum]]}} <- Cache.Repo.query("PRAGMA auto_vacuum"),
         {:ok, %{rows: [[freelist_count]]}} <- Cache.Repo.query("PRAGMA freelist_count"),
         {:ok, %{rows: [[page_count]]}} <- Cache.Repo.query("PRAGMA page_count"),
         {:ok, %{rows: [[page_size]]}} <- Cache.Repo.query("PRAGMA page_size") do
      in_use_bytes = (page_count - freelist_count) * page_size
      reclaimable_bytes = freelist_count * page_size

      case auto_vacuum do
        0 ->
          Logger.warning(
            "SQLite auto_vacuum is disabled (value: 0). " <>
              "Storage health: in_use=#{in_use_bytes} bytes, " <>
              "reclaimable=#{reclaimable_bytes} bytes, " <>
              "page_count=#{page_count}, page_size=#{page_size}"
          )

        2 ->
          Logger.info(
            "SQLite auto_vacuum is incremental (value: 2). " <>
              "Storage health: in_use=#{in_use_bytes} bytes, " <>
              "reclaimable=#{reclaimable_bytes} bytes, " <>
              "page_count=#{page_count}, page_size=#{page_size}"
          )

        other ->
          Logger.info(
            "SQLite auto_vacuum value: #{other}. " <>
              "Storage health: in_use=#{in_use_bytes} bytes, " <>
              "reclaimable=#{reclaimable_bytes} bytes, " <>
              "page_count=#{page_count}, page_size=#{page_size}"
          )
      end
    else
      {:error, reason} ->
        Logger.warning("Failed to check SQLite health: #{inspect(reason)}")
    end
  end

  defp start_sentry_logger do
    if Application.get_env(:sentry, :dsn) do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    end
  end

  defp start_loki_logger do
    loki_url = System.get_env("LOKI_URL")

    if loki_url do
      LokiLoggerHandler.attach(:loki_handler,
        loki_url: loki_url,
        storage: :memory,
        labels: %{
          app: {:static, "tuist-cache"},
          service_name: {:static, "tuist-cache"},
          service_namespace: {:static, "tuist"},
          env: {:static, System.get_env("DEPLOY_ENV") || "production"},
          level: :level
        },
        structured_metadata: [
          :trace_id,
          :span_id,
          :request_id,
          :auth_account_handle,
          :selected_account_handle,
          :selected_project_handle
        ]
      )
    end
  end

  defp start_opentelemetry do
    if Application.get_env(:opentelemetry, :traces_exporter) != :none do
      OpentelemetryLoggerMetadata.setup()
      OpentelemetryBandit.setup()
      OpentelemetryPhoenix.setup(adapter: :bandit)
      OpentelemetryEcto.setup(event_prefix: [:cache, :repo])
      OpentelemetryFinch.setup()
      OpentelemetryBroadway.setup()
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    CacheWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
