defmodule Tuist.Runners.Catalog do
  @moduledoc """
  The set of `(vcpus, memory_gb)` shapes the Linux runner fleet
  exposes. Read from application config (`:tuist, :runner_linux_shapes`),
  the same list the Helm chart renders into `RunnerPool` CRs via
  `runnersFleetLinux.shapes`.

  Config rather than a K8s LIST: the shapes are a small, operator-
  controlled set that rarely changes, the dispatch path resolves pool
  names deterministically (`pool_name/2`) without needing to enumerate
  pods, and config works in every environment — local dev with no
  cluster, tests, and prod alike. The two lists (this config and the
  Helm values) must be kept in sync; they live in the same repo and
  are reviewed together.

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
  The shape tagged `default: true` in config — the one the profile
  backfill and the "new profile" form preselect. Returns `nil` when
  no default is tagged.
  """
  def default do
    Enum.find(list(), & &1.default?)
  end

  @doc """
  Pool name a profile resolves to. Mirrors the chart's render:
  `<release>-tuist-runner-pool-linux-<vcpus>vcpu-<gb>gb`. The
  prefix is read from app config so test envs can override.
  """
  def pool_name(vcpus, memory_gb) when is_integer(vcpus) and is_integer(memory_gb) do
    "#{pool_name_prefix()}-#{vcpus}vcpu-#{memory_gb}gb"
  end

  defp normalize(%{vcpus: vcpus, memory_gb: memory_gb} = shape) when is_integer(vcpus) and is_integer(memory_gb) do
    %{
      vcpus: vcpus,
      memory_gb: memory_gb,
      key: "#{vcpus}vcpu-#{memory_gb}gb",
      default?: Map.get(shape, :default, false)
    }
  end

  defp normalize(_), do: nil

  defp pool_name_prefix do
    :tuist
    |> Application.get_env(:runners, [])
    |> Keyword.get(:linux_pool_name_prefix, "tuist-runner-pool-linux")
  end
end
