defmodule Tuist.Runners.Catalog do
  @moduledoc """
  The set of `(vcpus, memory_gb)` shapes the Linux runner fleet
  exposes. Read from application config (`:tuist, :runner_linux_shapes`).

  **Single source of truth: the Helm `runnersFleetLinux.shapes` list.**
  Helm both renders the shape-keyed `RunnerPool` CRs *and* injects the
  same list into the server as `TUIST_RUNNER_LINUX_SHAPES` (JSON), which
  `config/runtime.exs` parses into `:runner_linux_shapes`. So in a
  managed deploy the pools and the server's view of them can't drift —
  they come from one place. `config/config.exs` carries a default for
  local dev, tests, and CI, where there's no cluster and the env var is
  unset.

  Config rather than a live K8s LIST: dispatch stays a pure, fast hot
  path (no apiserver dependency to decide where a job goes), the catalog
  is available with no cluster, and pool names resolve deterministically
  via `pool_name/2`.

  Backs both `Tuist.Runners.Profile`'s shape validation and the
  resources dropdown in the Profiles LiveView.
  """

  @doc """
  All configured shapes, deduped and sorted by `(vcpus, memory_gb)`.
  Returns `[]` only when `:runner_linux_shapes` is unset (it ships
  with a default in `config/config.exs`).
  """
  def list do
    :tuist
    |> Application.get_env(:runner_linux_shapes, [])
    |> Enum.map(&normalize/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn s -> {s.vcpus, s.memory_gb} end)
    |> Enum.sort_by(fn s -> {s.vcpus, s.memory_gb} end)
  end

  @doc """
  Look up a shape by `(vcpus, memory_gb)`. Returns `nil` when the
  shape isn't in the catalog (e.g., a profile points at a shape that
  has since been removed from config).
  """
  def find(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb) do
    Enum.find(list(), fn shape -> shape.vcpus == vcpus and shape.memory_gb == memory_gb end)
  end

  @doc """
  The shape tagged `default: true` in config — the one the "new
  profile" form preselects and the legacy `tuist-<env>-linux` alias
  resolves to. Returns `nil` when no default is tagged.
  """
  def default do
    Enum.find(list(), & &1.default?)
  end

  @doc """
  Name of the `RunnerPool` CR a profile of this shape dispatches to.
  Mirrors the chart's render of `runnersFleetLinux.shapes` in
  `runner-pool.yaml`: `<prefix>-<vcpus>vcpu-<gb>gb`, where the prefix is
  the `tuist.componentName` value Helm injects via
  `TUIST_RUNNERS_LINUX_POOL_NAME_PREFIX` (see
  `Tuist.Environment.runners_linux_pool_name_prefix/0`). Injecting it
  keeps the server's enqueue target identical to the rendered CR name
  regardless of the helm release name, so jobs never land on a fleet no
  Pod polls.
  """
  def pool_name(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb) do
    "#{Tuist.Environment.runners_linux_pool_name_prefix()}-#{vcpus}vcpu-#{memory_gb}gb"
  end

  @doc """
  Decode the JSON wire form of the catalog into the
  `:runner_linux_shapes` config shape (atom keys, `memoryGb` →
  `:memory_gb`). The inverse of how Helm serialises
  `runnersFleetLinux.shapes` with `toJson`: a JSON array of objects with
  `vcpus`, `memoryGb`, and an optional `default`; unknown keys are
  ignored.

  Returns the shapes list, or `:error` for anything that isn't a JSON
  array of objects.
  """
  def parse_shapes_json(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, list} when is_list(list) ->
        Enum.map(list, fn shape ->
          base = %{vcpus: shape["vcpus"], memory_gb: shape["memoryGb"]}
          if shape["default"] == true, do: Map.put(base, :default, true), else: base
        end)

      _ ->
        :error
    end
  end

  def parse_shapes_json(_), do: :error

  defp normalize(%{vcpus: vcpus, memory_gb: memory_gb} = shape) when is_integer(vcpus) and is_integer(memory_gb) do
    %{
      vcpus: vcpus,
      memory_gb: memory_gb,
      key: "#{vcpus}vcpu-#{memory_gb}gb",
      default?: Map.get(shape, :default, false)
    }
  end

  defp normalize(_), do: nil
end
