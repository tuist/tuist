defmodule Tuist.Runners.Catalog do
  @moduledoc """
  The set of `(vcpus, memory_gb)` shapes the Linux runner fleet
  currently exposes. Discovered from the K8s API by listing the
  Helm-managed `RunnerPool` CRs and reading their `tuist.dev/shape*`
  labels — so the Helm chart stays the single source of truth and
  the server picks up new shapes on the next cache miss.

  The catalog backs both `Tuist.Runners.Profile`'s shape validation
  and the resources dropdown in the Profiles LiveView.

  Cached at the `:tuist` Cachex level for 60 seconds; that's the
  same shape as the dispatch path's pool list cache, and longer
  than the Helm rollout window where stale data could affect a
  newly-rolled shape. The cache key is process-cluster-wide; the
  60-second TTL means a new shape entry takes at most a minute to
  appear in the UI dropdown after a chart upgrade.
  """

  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client

  require Logger

  @cache_ttl_ms 60_000
  @cache_key [__MODULE__, :shapes]

  @shape_label "tuist.dev/shape"
  @shape_vcpus_label "tuist.dev/shape-vcpus"
  @shape_memory_label "tuist.dev/shape-memory-gb"
  @shape_default_label "tuist.dev/shape-default"
  @managed_by_label "tuist.dev/managed-by"

  @doc """
  All shapes currently rendered into the cluster, sorted by
  `(vcpus, memory_gb)`. Returns `[]` when no shape pools exist (no
  Helm rollout yet, or `runnersFleetLinux.shapes` empty).
  """
  def list do
    cache_opts = [cache: cache_name()]

    case KeyValueStore.get(@cache_key, cache_opts) do
      nil ->
        shapes = fetch_shapes()

        if shapes != [] do
          KeyValueStore.put(@cache_key, shapes, Keyword.put(cache_opts, :ttl, @cache_ttl_ms))
        end

        shapes

      cached ->
        cached
    end
  end

  @doc """
  Look up a shape by `(vcpus, memory_gb)`. Returns `nil` when the
  shape isn't in the current catalog (e.g., a profile points at a
  shape Helm has since removed).
  """
  def find(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb) do
    Enum.find(list(), fn shape -> shape.vcpus == vcpus and shape.memory_gb == memory_gb end)
  end

  @doc """
  The shape Helm marked as default for new accounts (the single
  `tuist.dev/shape-default=true` entry). Returns `nil` when no
  default is tagged.
  """
  def default do
    Enum.find(list(), & &1.default?)
  end

  @doc """
  Pool name a profile resolves to. Mirrors the chart's render:
  `<release>-tuist-runner-pool-linux-<vcpus>vcpu-<gb>gb`. The
  release prefix is read from app config so test envs can override.
  """
  def pool_name(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb) do
    "#{pool_name_prefix()}-#{vcpus}vcpu-#{memory_gb}gb"
  end

  defp fetch_shapes do
    namespace = Environment.runners_namespace()

    case Client.list_runner_pools(namespace) do
      {:ok, items} ->
        items
        |> Enum.flat_map(&shape_from_pool/1)
        |> Enum.uniq_by(fn s -> {s.vcpus, s.memory_gb} end)
        |> Enum.sort_by(fn s -> {s.vcpus, s.memory_gb} end)

      {:error, reason} ->
        Logger.warning("runners: catalog list failed", reason: inspect(reason))
        []
    end
  end

  defp shape_from_pool(%{"metadata" => %{"labels" => labels}, "spec" => spec}) when is_map(labels) and is_map(spec) do
    with "helm" <- Map.get(labels, @managed_by_label),
         shape_key when is_binary(shape_key) and shape_key != "" <- Map.get(labels, @shape_label),
         {:ok, vcpus} <- read_integer_label(labels, @shape_vcpus_label),
         {:ok, memory_gb} <- read_integer_label(labels, @shape_memory_label) do
      [
        %{
          vcpus: vcpus,
          memory_gb: memory_gb,
          key: shape_key,
          default?: Map.get(labels, @shape_default_label) == "true",
          pool_dispatch_label: Map.get(spec, "dispatchLabel")
        }
      ]
    else
      _ -> []
    end
  end

  defp shape_from_pool(_), do: []

  defp read_integer_label(labels, key) do
    case Map.get(labels, key) do
      v when is_binary(v) and v != "" ->
        case Integer.parse(v) do
          {n, ""} -> {:ok, n}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp pool_name_prefix do
    :tuist
    |> Application.get_env(:runners, [])
    |> Keyword.get(:linux_pool_name_prefix, "tuist-runner-pool-linux")
  end

  @doc """
  Cache name backing the shape list. Returns the application-wide
  `:tuist` Cachex in prod; tests stub this to a per-test cache.
  """
  def cache_name, do: :tuist
end
