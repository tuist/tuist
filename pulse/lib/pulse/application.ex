defmodule Pulse.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Pulse.Alerting.Subscriptions
  alias Pulse.Auth.Issuer
  alias Pulse.Auth.JWKS
  alias Pulse.Auth.Membership
  alias Pulse.Codec.NIF
  alias Pulse.Health.StorageMonitor
  alias Pulse.Loki.Tail
  alias Pulse.PromQL.QuerySlots
  alias Pulse.PromQL.TaskSupervisor
  alias Pulse.Storage.Memory
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.CompactionWorker
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Storage.S3.RetentionWorker
  alias Pulse.Tenants.Purger

  @impl true
  def start(_type, _args) do
    :ok = NIF.ensure_log_metadata_api!()
    :ok = NIF.ensure_metric_metadata_api!()
    :ok = NIF.ensure_trace_metadata_api!()

    children =
      [
        Pulse.SelfMetrics,
        Pulse.IngestAdmission,
        Pulse.MemoryPressure,
        Pulse.Tenants,
        Pulse.Usage,
        Pulse.Metrics,
        PulseWeb.Telemetry,
        {Task.Supervisor,
         name: TaskSupervisor,
         max_children: Keyword.get(Application.get_env(:pulse, Pulse.QueryRunner, []), :max_global, 4)},
        {Registry, keys: :unique, name: QuerySlots},
        Subscriptions,
        {DNSCluster, query: Application.get_env(:pulse, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Pulse.PubSub},
        Tail
      ] ++
        storage_children() ++
        maintenance(Pulse.Alerting.Supervisor.children()) ++
        JWKS.children() ++ issuer_children() ++ [PulseWeb.Endpoint] ++ otlp_grpc_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Background workers run only on instances with the maintenance role.
  defp maintenance(children), do: if(Pulse.Roles.enabled?(:maintenance), do: children, else: [])

  # Issuer keys and status are cached before the endpoint accepts traffic. The
  # membership scope lets instances divide tenant quotas among themselves.
  defp issuer_children do
    case Issuer.children() do
      [] -> []
      cache -> [%{id: Membership, start: {:pg, :start_link, [Membership]}} | cache]
    end
  end

  # The OTLP/gRPC listener starts after the endpoint, only when configured.
  defp otlp_grpc_children do
    config = Application.get_env(:pulse, PulseWeb.OTLPGRPC, [])

    if Keyword.get(config, :enabled, false) and Pulse.Roles.enabled?(:ingest),
      do: [{PulseWeb.OTLPGRPC, config |> Keyword.delete(:enabled) |> Keyword.put(:name, PulseWeb.OTLPGRPC)}],
      else: []
  end

  # `Memory` only runs when it is the configured adapter — in `mix test` no
  # adapter is set, so `Pulse.Storage.adapter/0` falls back to it. In dev and
  # prod the S3 adapter is configured and Memory would just be dead weight.
  #
  # The manifest layer (registry + dynamic supervisor + ETS cache) is only
  # started when the S3 adapter is active; other adapters have no manifest.
  defp storage_children do
    adapter =
      case Application.get_env(:pulse, Pulse.Storage) do
        nil -> nil
        env -> Keyword.get(env, :adapter)
      end

    case adapter do
      nil ->
        [Memory]

      Memory ->
        [Memory]

      S3 ->
        :ok = Pulse.ObjectStore.ensure_retention_api!()
        config = :pulse |> Application.fetch_env!(S3) |> Map.new()

        [ManifestSupervision, {StorageMonitor, config: config}] ++
          maintenance(
            CompactionWorker.children(config) ++
              RetentionWorker.children(config) ++
              Pulse.Errors.Supervisor.children() ++
              Pulse.Reliability.Supervisor.children() ++
              Purger.children()
          )

      _ ->
        []
    end
  end
end
