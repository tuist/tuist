defmodule Tuist.Runners.Catalog do
  @moduledoc """
  The set of `(vcpus, memory_gb)` shapes and (on macOS) Xcode versions
  the runner fleets expose. Read from application config:

    * `:runner_linux_shapes` — Linux shape catalog.
    * `:runner_macos_shapes` — macOS shape catalog (M2-L only today).
    * `:runner_macos_xcode_versions` — Xcode versions runnable on the
      macOS fleet.

  **Single source of truth: the Helm `runnersFleetLinux.shapes`,
  `runnersFleet.shapes`, and `runnersFleet.xcodeVersions` lists.**
  Helm both renders the corresponding `RunnerPool` CRs *and* injects
  the same lists into the server as `TUIST_RUNNER_LINUX_SHAPES`,
  `TUIST_RUNNER_MACOS_SHAPES`, and `TUIST_RUNNER_MACOS_XCODE_VERSIONS`
  (JSON), which `config/runtime.exs` parses into the matching config
  keys. So in a managed deploy the pools and the server's view of
  them can't drift — they come from one place. `config/config.exs`
  carries defaults for local dev, tests, and CI, where there's no
  cluster and the env vars are unset.

  Config rather than a live K8s LIST: dispatch stays a pure, fast hot
  path (no apiserver dependency to decide where a job goes), the
  catalog is available with no cluster, and pool names resolve
  deterministically via `pool_name/1`.

  Backs both `Tuist.Runners.Profile`'s validation and the resources
  / Xcode dropdowns in the Profiles LiveView.
  """

  @platforms [:linux, :macos]

  @doc """
  All shapes for `platform`, deduped and sorted by
  `(vcpus, memory_gb)`. Returns `[]` when the corresponding config
  key is unset (both keys ship with a default in `config/config.exs`).
  """
  def shapes(platform) when platform in @platforms do
    raw =
      case Application.get_env(:tuist, shapes_config_key(platform), []) do
        list when is_list(list) -> list
        _ -> []
      end

    raw
    |> Enum.map(&normalize_shape/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn s -> {s.vcpus, s.memory_gb} end)
    |> Enum.sort_by(fn s -> {s.vcpus, s.memory_gb} end)
  end

  @doc """
  Look up a shape on `platform` by `(vcpus, memory_gb)`. Returns
  `nil` when the shape isn't in the catalog (e.g., a profile points
  at a shape that has since been removed from config).
  """
  def find_shape(platform, vcpus, memory_gb)
      when platform in @platforms and is_integer(vcpus) and is_integer(memory_gb) do
    Enum.find(shapes(platform), fn shape ->
      shape.vcpus == vcpus and shape.memory_gb == memory_gb
    end)
  end

  @doc """
  The shape tagged `default: true` for `platform` — the one the
  "new profile" form preselects and the legacy alias resolves to.
  Returns `nil` when no default is tagged.
  """
  def default_shape(platform) when platform in @platforms do
    Enum.find(shapes(platform), & &1.default?)
  end

  @doc """
  All Xcode versions supported on the macOS fleet, deduped and
  sorted descending (newest first — the default preselect renders
  at the top of the form dropdown). Xcode is macOS-only, so this
  function takes no platform argument.
  """
  def xcode_versions do
    raw =
      case Application.get_env(:tuist, :runner_macos_xcode_versions, []) do
        list when is_list(list) -> list
        _ -> []
      end

    raw
    |> Enum.map(&normalize_xcode_version/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.xcode_version)
    |> Enum.sort_by(& &1.xcode_version, :desc)
  end

  @doc """
  Look up an Xcode version in the macOS catalog. Returns `nil` if
  absent.
  """
  def find_xcode_version(version) when is_binary(version) do
    Enum.find(xcode_versions(), fn x -> x.xcode_version == version end)
  end

  @doc """
  The Xcode version tagged `default: true` in the macOS catalog —
  what the "new profile" form preselects. Returns `nil` if none.
  """
  def default_xcode_version do
    Enum.find(xcode_versions(), & &1.default?)
  end

  @doc """
  Name of the `RunnerPool` CR a profile dispatches to.

    * `:linux` — `<linux-prefix>-<vcpus>vcpu-<memory_gb>gb` (e.g.
      `tuist-runner-pool-linux-4vcpu-16gb`). Prefix injected via
      `TUIST_RUNNERS_LINUX_POOL_NAME_PREFIX`.
    * `:macos` — `<macos-prefix>-<xcode-version-dashes>` (e.g.
      `tuist-runner-pool-macos-26-5`). M2-L is implicit today;
      when additional shapes ship, the shape suffix joins. Prefix
      injected via `TUIST_RUNNERS_MACOS_POOL_NAME_PREFIX`.

  Accepts any map with the relevant fields — `%Profile{}` works, as
  does a plain `%{platform: ..., vcpus: ..., memory_gb: ...}`.
  """
  def pool_name(%{platform: :linux, vcpus: vcpus, memory_gb: memory_gb})
      when is_integer(vcpus) and is_integer(memory_gb) do
    "#{Tuist.Environment.runners_linux_pool_name_prefix()}-#{vcpus}vcpu-#{memory_gb}gb"
  end

  def pool_name(%{platform: :macos, xcode_version: xcode_version})
      when is_binary(xcode_version) and xcode_version != "" do
    "#{Tuist.Environment.runners_macos_pool_name_prefix()}-#{xcode_version_tag(xcode_version)}"
  end

  @doc """
  `fleet_name` prefixes that identify `platform` jobs in
  `runner_jobs.fleet_name`. Used by the platform filter + the
  per-platform analytics grouping so profile-dispatched jobs surface
  alongside the legacy ones, not under the catch-all "Other" bucket.

  `:linux` accepts:

    * `"linux-…"` — legacy pre-catalog single per-env Linux pool.
    * `"<linux-prefix>-…"` — shape-catalog pool names that profile
      / legacy-alias dispatch produces (e.g.
      `tuist-runner-pool-linux-4vcpu-16gb`).

  `:macos` accepts:

    * `"macos-…"` — legacy pre-profile single per-env macOS pool.
    * `"<macos-prefix>-…"` — profile-dispatched macOS pool names
      (e.g. `tuist-runner-pool-macos-26-5`).
  """
  def fleet_name_prefixes(:linux) do
    ["linux-", Tuist.Environment.runners_linux_pool_name_prefix() <> "-"]
  end

  def fleet_name_prefixes(:macos) do
    ["macos-", Tuist.Environment.runners_macos_pool_name_prefix() <> "-"]
  end

  @doc """
  Decode the JSON wire form of the shape catalog into the
  `:runner_*_shapes` config shape (atom keys, `memoryGb` →
  `:memory_gb`). The inverse of how Helm serialises the chart's
  `shapes` lists with `toJson`: a JSON array of objects with
  `vcpus`, `memoryGb`, and an optional `default`; unknown keys are
  ignored.

  Returns the shapes list, or `:error` for anything that isn't a
  JSON array of objects.
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

  @doc """
  Decode the JSON wire form of the macOS Xcode catalog into the
  `:runner_macos_xcode_versions` config shape (atom keys,
  `xcodeVersion` → `:xcode_version`). Mirrors `parse_shapes_json/1`
  for the macOS-side `xcodeVersions` Helm list.
  """
  def parse_xcode_versions_json(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, list} when is_list(list) ->
        Enum.map(list, fn entry ->
          base = %{xcode_version: entry["xcodeVersion"]}
          if entry["default"] == true, do: Map.put(base, :default, true), else: base
        end)

      _ ->
        :error
    end
  end

  def parse_xcode_versions_json(_), do: :error

  defp shapes_config_key(:linux), do: :runner_linux_shapes
  defp shapes_config_key(:macos), do: :runner_macos_shapes

  defp normalize_shape(%{vcpus: vcpus, memory_gb: memory_gb} = shape) when is_integer(vcpus) and is_integer(memory_gb) do
    %{
      vcpus: vcpus,
      memory_gb: memory_gb,
      key: "#{vcpus}vcpu-#{memory_gb}gb",
      default?: Map.get(shape, :default, false)
    }
  end

  defp normalize_shape(_), do: nil

  defp normalize_xcode_version(%{xcode_version: version} = entry) when is_binary(version) and version != "" do
    %{
      xcode_version: version,
      tag: xcode_version_tag(version),
      default?: Map.get(entry, :default, false)
    }
  end

  defp normalize_xcode_version(_), do: nil

  # `26.5` → `26-5`, `26.4.1` → `26-4-1`. Matches the
  # `ghcr.io/tuist/tuist-runner:macos-<version-tag>` tag scheme the
  # runner-image release publishes.
  defp xcode_version_tag(version) when is_binary(version) do
    String.replace(version, ".", "-")
  end
end
