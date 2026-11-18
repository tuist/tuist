defmodule Tuist.TestImpactAnalysis.BuildSystem do
  @moduledoc """
  What coverage-based test selection reads from each build system that
  selects, so the shared code never names one:

  - its block in the baseline and runs requests (`xcode`, `mix`), whose
    keys an impact run stores as its `build_context`;
  - the key of that block that scopes baselines (`scheme`), which the
    generic `scope` of a request takes precedence over: a baseline's
    checkpoint must be of the same scheme, and a request without one accepts
    any;
  - how a shard plan distributes a selection: Xcode's by the suites with
    selected tests, each shard reading the skip list of its own suites; Mix's
    by the modules the plan job sends (which already leave out the ones with
    nothing selected), each shard reading the whole skip list and keeping
    what its test files hold, since a Mix shard runs files.
  """

  @build_systems %{
    "xcode" => %{block: :xcode, keys: ~w(scheme test_plan destination), shards: "suite"},
    "mix" => %{block: :mix, keys: ~w(scheme app), shards: "module"}
  }

  @doc "Whether projects of the build system select tests by coverage."
  def selects?(build_system), do: Map.has_key?(@build_systems, to_string(build_system))

  # Kept in every build system's context: the scope (as `scheme`) and the
  # coverage policy the runs request chose.
  @generic_keys ~w(scheme coverage_policy)

  @doc """
  The build context a request names in its build system's block, as the
  string-keyed map an impact run stores, with its scope as `scheme` and its
  `coverage_policy`. Without a block (a build system without one, or a
  request that sends none) only those two.
  """
  def context(params) do
    generic =
      for {key, value} <- [{"scheme", scheme(params)}, {"coverage_policy", Map.get(params, :coverage_policy)}],
          is_binary(value),
          into: %{},
          do: {key, value}

    Map.merge(block_context(params), generic)
  end

  @doc """
  The scheme a request scopes its baseline to: its generic `scope`, or else
  its block's `scheme`; nil for any.
  """
  def scheme(params), do: Map.get(params, :scope) || Map.get(block_context(params), "scheme")

  @doc "Every build context key a stored impact run may hold."
  def context_keys,
    do: @build_systems |> Map.values() |> Enum.flat_map(& &1.keys) |> Enum.concat(@generic_keys) |> Enum.uniq()

  defp block_context(params) do
    case Map.get(@build_systems, to_string(Map.get(params, :build_system))) do
      %{block: block, keys: keys} ->
        for {key, value} <- Map.get(params, block) || %{},
            key = to_string(key),
            key in keys,
            is_binary(value),
            into: %{},
            do: {key, value}

      nil ->
        %{}
    end
  end

  @doc """
  The granularity a shard plan of the build system's selection uses:
  `"suite"` (Xcode, and any build system without its own) or `"module"`.
  """
  def shard_granularity(build_system) do
    case Map.get(@build_systems, to_string(build_system)) do
      %{shards: granularity} -> granularity
      nil -> "suite"
    end
  end
end
