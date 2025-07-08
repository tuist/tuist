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

  def selective_testing_analytics(run, flop_params \\ %{}) do
    storage_module().selective_testing_analytics(run, flop_params)
  end

  def binary_cache_analytics(run, flop_params \\ %{}) do
    storage_module().binary_cache_analytics(run, flop_params)
  end

  def selective_testing_counts(run) do
    counts = storage_module().selective_testing_counts(run)
    Map.put(counts, :total_modules_count, counts.total_count)
  end

  def binary_cache_counts(run) do
    counts = storage_module().binary_cache_counts(run)
    Map.put(counts, :total_targets_count, counts.total_count)
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
  Shared validation for hit values from external metadata.
  """
  def normalize_hit_value(value) when value in ["miss", "local", "remote"], do: String.to_atom(value)

  def normalize_hit_value(_), do: :miss
end
