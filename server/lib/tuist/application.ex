defmodule Tuist.Application do
  @moduledoc false

  use Application
  use Boundary, top_level?: true, deps: [Tuist, TuistWeb]

  alias Tuist.Builds.Build
  alias Tuist.Builds.BuildFile
  alias Tuist.Builds.BuildIssue
  alias Tuist.Builds.BuildMachineMetric
  alias Tuist.Builds.BuildTarget
  alias Tuist.Builds.CacheableTask
  alias Tuist.Builds.CASOutput
  alias Tuist.Bundles.BundleIngest
  alias Tuist.Cache.CASEvent
  alias Tuist.CommandEvents
  alias Tuist.DBConnection.TelemetryListener
  alias Tuist.Docs.ContentFileWatcher
  alias Tuist.Docs.NimblePublisher.Cache
  alias Tuist.Environment
  alias Tuist.Gradle
  alias Tuist.Gradle.Build.Buffer
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseEvent
  alias Tuist.Tests.TestCaseFailure
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunArgument
  alias Tuist.Tests.TestCaseRunAttachment
  alias Tuist.Tests.TestCaseRunRepetition
  alias Tuist.Tests.TestModuleRun
  alias Tuist.Tests.TestSuiteRun
  alias Tuist.Xcode.XcodeGraph
  alias Tuist.Xcode.XcodeProject
  alias Tuist.Xcode.XcodeTarget
  alias TuistCommon.HTTP.TransportLogger

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Tuist version #{Environment.version()}")

    load_secrets_in_application()
    start_posthog()
    start_telemetry()
    start_sentry_logger()
    start_loki_logger()
    EMCP.SessionStore.ETS.init()

    application =
      Supervisor.start_link(get_children(), strategy: :one_for_one, name: Tuist.Supervisor)

    Logger.info("Tuist application started")

    Tuist.License.assert_valid!()

    application
  end

  defp load_secrets_in_application do
    Environment.put_application_secrets(Environment.decrypt_secrets())
  end

  defp start_posthog do
    if Environment.analytics_enabled?() do
      case Application.start(:posthog) do
        :ok ->
          Logger.info("PostHog analytics started")

        {:error, {:already_started, _}} ->
          Logger.info("PostHog analytics already started")

        {:error, reason} ->
          Logger.warning("Failed to start PostHog analytics: #{inspect(reason)}")
      end
    end
  end

  defp start_telemetry do
    Oban.Telemetry.attach_default_logger()
    TuistCommon.ObanTelemetry.attach()
    ReqTelemetry.attach_default_logger(:pipeline)
    TransportLogger.attach(:tuist)

    if Application.get_env(:opentelemetry, :traces_exporter) != :none do
      OpentelemetryLoggerMetadata.setup()
      OpentelemetryBandit.setup()
      OpentelemetryPhoenix.setup(adapter: :bandit)
      OpentelemetryFinch.setup()
      OpentelemetryBroadway.setup()
      ecto_skip_metrics = [additional_span_attributes: %{:"metrics.skip" => true}]
      OpentelemetryEcto.setup([event_prefix: [:tuist, :repo]] ++ ecto_skip_metrics)
      OpentelemetryEcto.setup([event_prefix: [:tuist, :ingest_repo]] ++ ecto_skip_metrics)
      OpentelemetryEcto.setup([event_prefix: [:tuist, :click_house_repo]] ++ ecto_skip_metrics)

      kick_opentelemetry_exporter_after_boot()
    end
  end

  # opentelemetry_exporter starts as part of :extra_applications at release
  # boot — before the pod's ClusterIP Service DNS is guaranteed to resolve
  # (especially true just after pod start on k8s, where kube-dns can lag).
  # Its very first export attempt hits :no_endpoints and the batch processor
  # never recovers — subsequent spans are silently dropped.
  #
  # Workaround: stop + start the exporter a few seconds later, once DNS is
  # up. The fresh gRPC channel resolves the endpoint correctly and from
  # then on export works normally.
  defp kick_opentelemetry_exporter_after_boot do
    spawn_supervised_task(fn -> do_kick_opentelemetry_exporter() end)
  end

  defp do_kick_opentelemetry_exporter do
    Process.sleep(8_000)

    case Application.stop(:opentelemetry_exporter) do
      :ok ->
        case Application.start(:opentelemetry_exporter) do
          :ok ->
            Logger.info("Restarted :opentelemetry_exporter to clear boot-time :no_endpoints state")

          {:error, reason} ->
            Logger.warning("Failed to restart :opentelemetry_exporter: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Failed to stop :opentelemetry_exporter for restart: #{inspect(reason)}")
    end
  end

  # Start a fire-and-forget task with crash-reporting wrapped around it.
  # `Task.start/1` swallows exceptions silently; wrapping the body in a
  # `try/rescue` guarantees anything that goes wrong reaches Logger (and
  # Sentry via the Sentry logger handler).
  defp spawn_supervised_task(fun) do
    Task.start(fn ->
      try do
        fun.()
      rescue
        e ->
          Logger.error(
            "Unhandled exception in background task: #{Exception.message(e)}\n" <>
              Exception.format_stacktrace(__STACKTRACE__)
          )
      end
    end)
  end

  defp start_sentry_logger do
    if Environment.error_tracking_enabled?() do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    end
  end

  defp start_loki_logger do
    loki_url = Environment.loki_url()

    # Setting TUIST_LOKI_URL attaches an in-process log handler that
    # pushes each event to Loki directly. Attach in the background with
    # retry so a slow DNS / CNI startup doesn't fail the first attempt.
    if loki_url do
      spawn_supervised_task(fn -> attach_loki_handler_with_retry(loki_url, 0) end)
    end
  end

  @loki_attach_max_attempts 10
  @loki_attach_base_backoff_ms 1_000
  @loki_attach_max_backoff_ms 30_000

  defp attach_loki_handler_with_retry(loki_url, attempt) when attempt < @loki_attach_max_attempts do
    # Exponential backoff capped at @loki_attach_max_backoff_ms. Total
    # wait across 10 attempts is ~5 min, which covers the longest DNS /
    # CNI propagation delays we've seen on k8s after a fresh pod schedule.
    backoff =
      @loki_attach_base_backoff_ms
      |> Kernel.*(:math.pow(2, attempt))
      |> round()
      |> min(@loki_attach_max_backoff_ms)

    Process.sleep(backoff)

    # Call :logger.add_handler/3 directly so we can set filters + overload
    # options that LokiLoggerHandler.attach/2 doesn't expose:
    #
    #   - `filters`: drop log events whose module is inside LokiLoggerHandler
    #     itself. Its Sender emits Logger.warning on failed pushes, and those
    #     warnings would otherwise re-enter this handler, get buffered, fail
    #     to push, emit another warning, and so on. The kernel logger kills
    #     overloaded handlers (removed_failing_handler), so this amplification
    #     was disabling the handler within a few seconds of startup.
    #   - `overload_kill_enable: false`: additional guard so transient bursts
    #     (e.g., a retry storm after Alloy restarts) don't permanently kill
    #     the handler.
    handler_config = %{
      loki_url: loki_url,
      storage: :memory,
      labels: %{
        app: {:static, "tuist-server"},
        service_name: {:static, "tuist-server"},
        service_namespace: {:static, "tuist"},
        env: {:static, to_string(Environment.env())},
        level: :level
      },
      structured_metadata: [
        :trace_id,
        :span_id,
        :request_id,
        :auth_account_handle,
        :selected_account_handle,
        :selected_project_handle,
        :method,
        :route,
        :request_path,
        :reason,
        :error,
        :kind,
        :event,
        :duration_ms,
        :remote_address,
        :remote_port,
        :recv_oct,
        :send_oct,
        :req_body_bytes,
        :request_span_context,
        :connection_span_context
      ]
    }

    logger_config = %{
      config: handler_config,
      filters: [
        loki_self_logs: {&__MODULE__.filter_loki_self_logs/2, []}
      ],
      filter_default: :log,
      overload_kill_enable: false
    }

    case :logger.add_handler(:loki_handler, LokiLoggerHandler.Handler, logger_config) do
      :ok ->
        Logger.info("LokiLoggerHandler attached after #{attempt + 1} attempt(s)")

      {:error, reason} ->
        Logger.warning("LokiLoggerHandler attach attempt #{attempt + 1} failed: #{inspect(reason)} — retrying")

        attach_loki_handler_with_retry(loki_url, attempt + 1)
    end
  end

  defp attach_loki_handler_with_retry(_loki_url, _attempt) do
    Logger.error("LokiLoggerHandler attach gave up after #{@loki_attach_max_attempts} attempts")
  end

  # :logger filter callback. Drops log events that originated inside
  # LokiLoggerHandler itself — prevents a feedback loop where failed-push
  # warnings get buffered and retried, amplifying the queue until the kernel
  # kills the handler. Must be a public function for :logger to resolve it.
  @doc false
  def filter_loki_self_logs(log_event, _extra) do
    case log_event do
      %{meta: %{mfa: {module, _function, _arity}}} ->
        mod_str = Atom.to_string(module)

        if String.starts_with?(mod_str, "Elixir.LokiLoggerHandler") do
          :stop
        else
          :ignore
        end

      _ ->
        :ignore
    end
  end

  defp get_children do
    children =
      [
        {DBConnection.TelemetryListener, name: TelemetryListener},
        {Tuist.Repo, connection_listeners: {[TelemetryListener], :postgres}},
        {Tuist.ClickHouseRepo, connection_listeners: {[TelemetryListener], :clickhouse_read}},
        {Tuist.IngestRepo, connection_listeners: {[TelemetryListener], :clickhouse_write}},
        Supervisor.child_spec(CommandEvents.Event.Buffer, id: CommandEvents.Event.Buffer),
        Supervisor.child_spec(Build.Buffer, id: Build.Buffer),
        Supervisor.child_spec(BundleIngest.Buffer, id: BundleIngest.Buffer),
        Supervisor.child_spec(BuildFile.Buffer, id: BuildFile.Buffer),
        Supervisor.child_spec(BuildIssue.Buffer, id: BuildIssue.Buffer),
        Supervisor.child_spec(BuildMachineMetric.Buffer, id: BuildMachineMetric.Buffer),
        Supervisor.child_spec(BuildTarget.Buffer, id: BuildTarget.Buffer),
        Supervisor.child_spec(CacheableTask.Buffer, id: CacheableTask.Buffer),
        Supervisor.child_spec(CASOutput.Buffer, id: CASOutput.Buffer),
        Supervisor.child_spec(XcodeGraph.Buffer, id: XcodeGraph.Buffer),
        Supervisor.child_spec(XcodeProject.Buffer, id: XcodeProject.Buffer),
        Supervisor.child_spec(XcodeTarget.Buffer, id: XcodeTarget.Buffer),
        Supervisor.child_spec(Buffer, id: Buffer),
        Supervisor.child_spec(Gradle.Task.Buffer, id: Gradle.Task.Buffer),
        Supervisor.child_spec(TestCaseRun.Buffer, id: TestCaseRun.Buffer),
        Supervisor.child_spec(TestModuleRun.Buffer, id: TestModuleRun.Buffer),
        Supervisor.child_spec(TestSuiteRun.Buffer, id: TestSuiteRun.Buffer),
        Supervisor.child_spec(TestCase.Buffer, id: TestCase.Buffer),
        Supervisor.child_spec(TestCaseFailure.Buffer, id: TestCaseFailure.Buffer),
        Supervisor.child_spec(TestCaseRunRepetition.Buffer, id: TestCaseRunRepetition.Buffer),
        Supervisor.child_spec(TestCaseRunArgument.Buffer, id: TestCaseRunArgument.Buffer),
        Supervisor.child_spec(TestCaseRunAttachment.Buffer, id: TestCaseRunAttachment.Buffer),
        Supervisor.child_spec(TestCaseEvent.Buffer, id: TestCaseEvent.Buffer),
        Supervisor.child_spec(CASEvent.Buffer, id: CASEvent.Buffer),
        Tuist.Vault,
        {Oban, Application.fetch_env!(:tuist, Oban)},
        {Cachex, [:tuist, []]},
        {Finch, name: Tuist.Finch, pools: finch_pools()},
        {Phoenix.PubSub, name: Tuist.PubSub},
        {TuistWeb.RateLimit.InMemory, [clean_period: to_timeout(hour: 1)]},
        {Tuist.API.Pipeline, []},
        {Guardian.DB.Sweeper, [interval: 60 * 60 * 1000]},
        TuistWeb.Telemetry
      ] ++ dev_content_children() ++ [TuistWeb.Endpoint]

    children
    |> Kernel.++(
      if Environment.dev_use_remote_storage?() do
        []
      else
        %{port: minio_port, scheme: minio_scheme} = URI.parse(Environment.s3_endpoint())
        port = minio_port || 9095
        console_port = Environment.minio_console_port()

        {minio_path, 0} = System.cmd("mise", ["which", "minio"])

        minio_path = String.trim(minio_path)

        [
          {MinioServer,
           name: :minio_dev,
           port: port,
           scheme: minio_scheme,
           region: Environment.s3_region(),
           access_key_id: Environment.s3_access_key_id(),
           secret_access_key: Environment.s3_secret_access_key(),
           minio_executable: minio_path,
           console_address: ":#{console_port}"},
          Tuist.MinioBucketCreator
        ]
      end
    )
    |> Kernel.++(
      if Environment.tuist_hosted?() do
        topologies = Application.get_env(:libcluster, :topologies) || []
        [{Cluster.Supervisor, [topologies, [name: Tuist.ClusterSupervisor]]}]
      else
        []
      end
    )
    |> Kernel.++(
      if Environment.redis_url(),
        do: [
          {Redix, redis_opts()},
          {TuistWeb.RateLimit.PersistentTokenBucket, redis_opts()}
        ],
        else: []
    )
    # Marketing.Stats polls ClickHouse on init. Skip it in test (tables
    # may not exist) and dev (noisy debug logs every 5 s).
    |> Kernel.++(
      if Environment.test?() or Environment.dev?(),
        do: [],
        else: [Tuist.Marketing.Stats]
    )
  end

  defp dev_content_children do
    if Environment.dev?() do
      docs_dirs = [
        Path.expand("../../priv/docs", __DIR__),
        Path.expand("../../../examples/xcode", __DIR__)
      ]

      marketing_dirs = [
        Path.expand("../../priv/marketing", __DIR__)
      ]

      [
        Cache,
        Supervisor.child_spec(
          {Tuist.ContentFileWatcher, name: ContentFileWatcher, dirs: docs_dirs, extensions: [".md"], cache: Cache},
          id: ContentFileWatcher
        ),
        Tuist.Marketing.NimblePublisher.Cache,
        Supervisor.child_spec(
          {Tuist.ContentFileWatcher,
           name: Tuist.Marketing.ContentFileWatcher,
           dirs: marketing_dirs,
           extensions: [".md", ".yml"],
           cache: Tuist.Marketing.NimblePublisher.Cache},
          id: Tuist.Marketing.ContentFileWatcher
        )
      ]
    else
      []
    end
  end

  defp finch_pools do
    if Environment.test?() do
      %{:default => [size: 10]}
    else
      {s3_endpoint, s3_pool_opts} =
        TuistCommon.FinchPools.s3_pool(
          endpoint: Environment.s3_endpoint(),
          size: Environment.s3_pool_size(),
          count: Environment.s3_pool_count(),
          protocols: Environment.s3_protocols(),
          use_ipv6: Environment.use_ipv6?() in ~w(true 1),
          ca_cert_pem: Environment.s3_ca_cert_pem()
        )

      base_pools =
        %{
          :default => [size: 10, start_pool_metrics?: true],
          "https://api.github.com" => [
            conn_opts: [
              log: true,
              protocols: [:http2, :http1],
              transport_opts: [
                inet6: Environment.use_ipv6?() in ~w(true 1),
                cacertfile: CAStore.file_path(),
                verify: :verify_peer
              ]
            ],
            size: 10,
            count: 2,
            protocols: [:http2, :http1],
            start_pool_metrics?: true
          ],
          s3_endpoint => s3_pool_opts,
          "https://marketing.tuist.dev" => [
            conn_opts: [
              log: true,
              protocols: [:http2, :http1],
              transport_opts: [
                inet6: Environment.use_ipv6?() in ~w(true 1),
                cacertfile: CAStore.file_path(),
                verify: :verify_peer
              ]
            ],
            size: 10,
            count: 1,
            protocols: [:http2, :http1],
            start_pool_metrics?: true
          ],
          Environment.posthog_url() => [
            conn_opts: [
              log: true,
              protocols: [:http2, :http1],
              transport_opts: [
                inet6: Environment.use_ipv6?() in ~w(true 1),
                cacertfile: CAStore.file_path(),
                verify: :verify_peer
              ]
            ],
            size: 5,
            count: 1,
            protocols: [:http2, :http1],
            start_pool_metrics?: true
          ]
        }
        |> Enum.reject(fn {key, _value} -> is_nil(key) end)
        |> Map.new()

      additional_pools =
        Map.new(Environment.additional_finch_pools(), fn {endpoint, config} ->
          {endpoint, build_additional_pool_opts(config)}
        end)

      Map.merge(base_pools, additional_pools)
    end
  end

  defp build_additional_pool_opts(config) when is_map(config) do
    size = Map.get(config, "size", 100)
    count = Map.get(config, "count", System.schedulers_online())

    [
      conn_opts: [
        log: true,
        protocols: [:http1],
        transport_opts: [
          inet6: Environment.use_ipv6?() in ~w(true 1),
          cacertfile: CAStore.file_path(),
          verify: :verify_peer
        ]
      ],
      size: size,
      count: count,
      protocols: [:http1],
      start_pool_metrics?: true
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TuistWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def redis_opts do
    %URI{} = parsed_url = URI.parse(Environment.redis_url())

    socket_opts =
      if Environment.use_ipv6?() in ~w(true 1),
        do: [:inet6, {:keepalive, true}],
        else: [{:keepalive, true}]

    opts = [
      name: Environment.redis_conn_name(),
      host: parsed_url.host,
      port: parsed_url.port,
      sync_connect: false,
      socket_opts: socket_opts
    ]

    case parsed_url.userinfo do
      nil ->
        opts

      userinfo ->
        auth_opts =
          case String.split(userinfo, ":", parts: 2) do
            [username] -> [username: username]
            [username, password] -> [username: username, password: password]
            _ -> []
          end

        Keyword.merge(opts, auth_opts)
    end
  end
end
