defmodule Tuist.Xcode do
  @moduledoc """
  Module for interacting with Xcode primitives such as Xcode graphs.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Xcode.XcodeGraph.Buffer, as: XcodeGraphBuffer
  alias Tuist.Xcode.XcodeProject.Buffer, as: XcodeProjectBuffer
  alias Tuist.Xcode.XcodeTarget
  alias Tuist.Xcode.XcodeTarget.Buffer, as: XcodeTargetBuffer

  require Logger

  def create_xcode_graph(%{command_event: %{id: command_event_id}, xcode_graph: %{name: name} = xcode_graph}) do
    {xcode_graph_data, projects_data, targets_data, xcode_graph_id} =
      prepare_xcode_graph(xcode_graph, command_event_id)

    XcodeGraphBuffer.insert(xcode_graph_data)
    XcodeProjectBuffer.insert(projects_data)
    XcodeTargetBuffer.insert(targets_data)

    xcode_graph = %{id: xcode_graph_id, name: name, command_event_id: command_event_id}
    {:ok, xcode_graph}
  end

  def selective_testing_analytics(run, flop_params \\ %{}) do
    base_query =
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash),
        select: %{
          id: xt.id,
          name: xt.name,
          selective_testing_hit: xt.selective_testing_hit,
          selective_testing_hash: xt.selective_testing_hash
        }
      )

    {targets, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, flop_params, for: XcodeTarget)

    test_modules =
      Enum.map(targets, fn target ->
        %{
          name: target.name,
          selective_testing_hit: String.to_existing_atom(target.selective_testing_hit),
          selective_testing_hash: target.selective_testing_hash
        }
      end)

    analytics = %{test_modules: test_modules}
    {analytics, meta}
  end

  def binary_cache_analytics(run, flop_params \\ %{}) do
    base_query =
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash),
        select: %{
          id: xt.id,
          name: xt.name,
          binary_cache_hit: xt.binary_cache_hit,
          binary_cache_hash: xt.binary_cache_hash,
          product: xt.product,
          bundle_id: xt.bundle_id,
          product_name: xt.product_name,
          external_hash: xt.external_hash,
          sources_hash: xt.sources_hash,
          resources_hash: xt.resources_hash,
          copy_files_hash: xt.copy_files_hash,
          core_data_models_hash: xt.core_data_models_hash,
          target_scripts_hash: xt.target_scripts_hash,
          environment_hash: xt.environment_hash,
          headers_hash: xt.headers_hash,
          deployment_target_hash: xt.deployment_target_hash,
          info_plist_hash: xt.info_plist_hash,
          entitlements_hash: xt.entitlements_hash,
          dependencies_hash: xt.dependencies_hash,
          project_settings_hash: xt.project_settings_hash,
          target_settings_hash: xt.target_settings_hash,
          buildable_folders_hash: xt.buildable_folders_hash,
          destinations: xt.destinations,
          additional_strings: xt.additional_strings
        }
      )

    {targets, meta} =
      Tuist.ClickHouseFlop.validate_and_run!(base_query, flop_params, for: XcodeTarget)

    cacheable_targets =
      Enum.map(targets, fn target ->
        %{
          name: target.name,
          binary_cache_hit: String.to_existing_atom(target.binary_cache_hit),
          binary_cache_hash: target.binary_cache_hash,
          product: target.product,
          bundle_id: target.bundle_id,
          product_name: target.product_name,
          external_hash: target.external_hash,
          sources_hash: target.sources_hash,
          resources_hash: target.resources_hash,
          copy_files_hash: target.copy_files_hash,
          core_data_models_hash: target.core_data_models_hash,
          target_scripts_hash: target.target_scripts_hash,
          environment_hash: target.environment_hash,
          headers_hash: target.headers_hash,
          deployment_target_hash: target.deployment_target_hash,
          info_plist_hash: target.info_plist_hash,
          entitlements_hash: target.entitlements_hash,
          dependencies_hash: target.dependencies_hash,
          project_settings_hash: target.project_settings_hash,
          target_settings_hash: target.target_settings_hash,
          buildable_folders_hash: target.buildable_folders_hash,
          destinations: target.destinations,
          additional_strings: target.additional_strings
        }
      end)

    analytics = %{cacheable_targets: cacheable_targets}
    {analytics, meta}
  end

  def selective_testing_counts(run) do
    result =
      ClickHouseRepo.one(
        from(xt in XcodeTarget,
          where: xt.command_event_id == ^run.id,
          where: not is_nil(xt.selective_testing_hash),
          select: %{
            local: fragment("countIf(selective_testing_hit = 'local')"),
            remote: fragment("countIf(selective_testing_hit = 'remote')"),
            miss: fragment("countIf(selective_testing_hit = 'miss')"),
            total: count(xt.id)
          }
        )
      )

    %{
      selective_testing_local_hits_count: result.local || 0,
      selective_testing_remote_hits_count: result.remote || 0,
      selective_testing_misses_count: result.miss || 0,
      total_count: result.total || 0,
      total_modules_count: result.total || 0
    }
  end

  def binary_cache_counts(run) do
    result =
      ClickHouseRepo.one(
        from(xt in XcodeTarget,
          where: xt.command_event_id == ^run.id,
          where: not is_nil(xt.binary_cache_hash),
          select: %{
            local: fragment("countIf(binary_cache_hit = 'local')"),
            remote: fragment("countIf(binary_cache_hit = 'remote')"),
            miss: fragment("countIf(binary_cache_hit = 'miss')"),
            total: count(xt.id)
          }
        )
      )

    local_count = result.local || 0
    remote_count = result.remote || 0
    total_hits = local_count + remote_count
    total = result.total || 0

    cache_hit_rate =
      if total > 0 do
        Float.round(total_hits / total * 100, 1)
      else
        0.0
      end

    %{
      binary_cache_local_hits_count: local_count,
      binary_cache_remote_hits_count: remote_count,
      binary_cache_misses_count: result.miss || 0,
      total_count: total,
      total_targets_count: total,
      cache_hit_rate: cache_hit_rate
    }
  end

  def has_selective_testing_data?(run) do
    ClickHouseRepo.exists?(
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.selective_testing_hash)
      )
    )
  end

  def has_binary_cache_data?(run) do
    ClickHouseRepo.exists?(
      from(xt in XcodeTarget,
        where: xt.command_event_id == ^run.id,
        where: not is_nil(xt.binary_cache_hash)
      )
    )
  end

  defp prepare_xcode_graph(xcode_graph, command_event_id) do
    xcode_graph_id = UUIDv7.generate()
    inserted_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    xcode_graph_data = %{
      id: xcode_graph_id,
      name: xcode_graph.name,
      command_event_id: command_event_id,
      binary_build_duration: Map.get(xcode_graph, :binary_build_duration),
      inserted_at: inserted_at
    }

    projects_data =
      Enum.map(xcode_graph.projects, fn project ->
        %{
          id: UUIDv7.generate(),
          command_event_id: command_event_id,
          xcode_graph_id: xcode_graph_id,
          name: project["name"],
          path: project["path"],
          inserted_at: inserted_at
        }
      end)

    targets_data =
      xcode_graph.projects
      |> Enum.map(fn project ->
        %{
          project: Enum.find(projects_data, &(&1.name == project["name"])),
          targets: project["targets"]
        }
      end)
      |> Enum.flat_map(fn xcode_project ->
        Enum.map(
          xcode_project.targets,
          &XcodeTarget.changeset(
            xcode_project.project.command_event_id,
            xcode_project.project.id,
            &1,
            inserted_at
          )
        )
      end)

    {xcode_graph_data, projects_data, targets_data, xcode_graph_id}
  end

  def normalize_hit_value(value) when value in ["miss", "local", "remote"], do: String.to_atom(value)

  def normalize_hit_value(_), do: :miss

  def humanize_xcode_target_destination("iphone"), do: "iPhone"
  def humanize_xcode_target_destination("ipad"), do: "iPad"
  def humanize_xcode_target_destination("mac"), do: "Mac"
  def humanize_xcode_target_destination("mac_with_ipad_design"), do: "Mac with iPad design"
  def humanize_xcode_target_destination("apple_watch"), do: "Apple Watch"
  def humanize_xcode_target_destination("apple_tv"), do: "Apple TV"
  def humanize_xcode_target_destination("apple_vision"), do: "Apple Vision"
  def humanize_xcode_target_destination(other), do: other
end
