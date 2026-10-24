defmodule Tuist.Builds.Metadata do
  @moduledoc """
  Semantics for the existing string-valued build metadata map.

  Recognition affects display only. Unknown keys and invalid observations remain
  ordinary metadata, and reported values never establish trusted identity.
  """

  @legacy_limit 20
  @limit 64
  @keys %{
    "tuist.os.type" => :string,
    "tuist.os.version" => :string,
    "tuist.os.kernel_version" => :string,
    "tuist.host.arch" => :string,
    "tuist.host.model" => :string,
    "tuist.cpu.available_processors" => :count,
    "tuist.memory.total_bytes" => :bytes,
    "tuist.process.locale" => :string,
    "tuist.process.charset" => :string,
    "tuist.jvm.vendor" => :string,
    "tuist.jvm.runtime_name" => :string,
    "tuist.jvm.runtime_version" => :string,
    "tuist.jvm.vm_name" => :string,
    "tuist.jvm.vm_version" => :string,
    "tuist.jvm.max_heap_bytes" => :bytes,
    "tuist.gradle.max_workers" => :count,
    "tuist.ci.provider" => :string,
    "tuist.ci.job" => :string,
    "tuist.ci.runner_environment" => :string,
    "tuist.ci.runner_name" => :string
  }

  def legacy_limit, do: @legacy_limit
  def limit, do: @limit

  def advertised_limit do
    if Tuist.Environment.expanded_build_metadata_enabled?(), do: @limit, else: @legacy_limit
  end

  def partition(values) when is_map(values) do
    values
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.split_with(fn {key, value} -> not is_nil(kind(key, value)) end)
  end

  def partition(_values), do: {[], []}

  def kind(key, value) when is_binary(value) do
    case Map.get(@keys, key) do
      :string ->
        if String.trim(value) != "", do: :string

      numeric when numeric in [:count, :bytes] ->
        case Integer.parse(value) do
          {number, ""} when number > 0 and number <= 9_007_199_254_740_991 -> numeric
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def kind(_key, _value), do: nil
end
