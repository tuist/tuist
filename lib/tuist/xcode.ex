defmodule Tuist.Xcode do
  @moduledoc """
  Module for interacting with Xcode primitives such as Xcode graphs.
  """

  alias Tuist.Environment

  require Logger

  defp storage_module do
    if Environment.clickhouse_configured?() do
      Tuist.Xcode.Clickhouse
    else
      Tuist.Xcode.Postgres
    end
  end

  def create_xcode_graph(attrs) do
    storage_module().create_xcode_graph(attrs)
  end

  def selective_testing_analytics(run) do
    storage_module().selective_testing_analytics(run)
  end

  def binary_cache_analytics(run) do
    storage_module().binary_cache_analytics(run)
  end

  def has_selective_testing_data?(run) do
    storage_module().has_selective_testing_data?(run)
  end

  def has_binary_cache_data?(run) do
    storage_module().has_binary_cache_data?(run)
  end

  def xcode_targets_for_command_event(command_event_id) do
    storage_module().xcode_targets_for_command_event(command_event_id)
  end

  @doc """
  Shared logic for counting analytics results by hit type.
  """
  def count_by_hit_type(items, hit_field) do
    %{
      local_hits_count: Enum.count(items, &(Map.get(&1, hit_field) == :local)),
      remote_hits_count: Enum.count(items, &(Map.get(&1, hit_field) == :remote)),
      misses_count: Enum.count(items, &(Map.get(&1, hit_field) == :miss))
    }
  end

  @doc """
  Shared logic for building analytics response structure.
  """
  def build_selective_testing_analytics(test_modules) do
    counts = count_by_hit_type(test_modules, :selective_testing_hit)

    %{
      test_modules: test_modules,
      selective_testing_local_hits_count: counts.local_hits_count,
      selective_testing_remote_hits_count: counts.remote_hits_count,
      selective_testing_misses_count: counts.misses_count
    }
  end

  @doc """
  Shared logic for building binary cache analytics response structure.
  """
  def build_binary_cache_analytics(cacheable_targets) do
    counts = count_by_hit_type(cacheable_targets, :binary_cache_hit)

    %{
      cacheable_targets: cacheable_targets,
      binary_cache_local_hits_count: counts.local_hits_count,
      binary_cache_remote_hits_count: counts.remote_hits_count,
      binary_cache_misses_count: counts.misses_count
    }
  end

  @doc """
  Shared validation for hit values from external metadata.
  """
  def normalize_hit_value(value) when value in ["miss", "local", "remote"], do: String.to_atom(value)

  def normalize_hit_value(_), do: :miss
end
