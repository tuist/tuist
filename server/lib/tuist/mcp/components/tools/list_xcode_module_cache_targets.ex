defmodule Tuist.MCP.Components.Tools.ListXcodeModuleCacheTargets do
  @moduledoc """
  List module cache targets for a generation or cache run, showing per-target cache hit/miss status and subhashes. Only available for projects with build_system=xcode. The run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/runs/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.CommandEvents
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Xcode

  @authorization_action :read
  @authorization_category :run

  schema do
    field :run_id, :string,
      required: true,
      description: "The ID of the generation or cache run."

    field :cache_status, :string, description: "Filter by cache status: miss, local, or remote."

    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(%{run_id: run_id} = arguments, frame) do
    with {:ok, event} <-
           ToolSupport.load_resource(
             get_command_event(run_id),
             "Run not found: #{run_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             event.project_id,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)

      flop_params = maybe_add_filter(%{page: page, page_size: page_size}, arguments)

      {analytics, meta} = Xcode.binary_cache_analytics(event, flop_params)

      data = %{
        targets:
          Enum.map(analytics.cacheable_targets, fn target ->
            %{
              name: target.name,
              cache_status: to_string(target.binary_cache_hit),
              cache_hash: target.binary_cache_hash,
              product: non_empty(target.product),
              bundle_id: non_empty(target.bundle_id),
              product_name: non_empty(target.product_name),
              subhashes: build_subhashes(target)
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp get_command_event(id) do
    case CommandEvents.get_command_event_by_id(id) do
      {:ok, event} when event.name in ["generate", "cache"] -> {:ok, event}
      {:ok, _event} -> {:error, :not_found}
      error -> error
    end
  end

  defp maybe_add_filter(flop_params, arguments) do
    case Map.get(arguments, :cache_status) do
      nil ->
        flop_params

      status ->
        Map.put(flop_params, :filters, [
          %{field: :binary_cache_hit, op: :==, value: status}
        ])
    end
  end

  defp non_empty(""), do: nil
  defp non_empty(value), do: value

  defp build_subhashes(target) do
    %{
      sources: non_empty(target.sources_hash),
      resources: non_empty(target.resources_hash),
      copy_files: non_empty(target.copy_files_hash),
      core_data_models: non_empty(target.core_data_models_hash),
      target_scripts: non_empty(target.target_scripts_hash),
      environment: non_empty(target.environment_hash),
      headers: non_empty(target.headers_hash),
      deployment_target: non_empty(target.deployment_target_hash),
      info_plist: non_empty(target.info_plist_hash),
      entitlements: non_empty(target.entitlements_hash),
      dependencies: non_empty(target.dependencies_hash),
      project_settings: non_empty(target.project_settings_hash),
      target_settings: non_empty(target.target_settings_hash),
      buildable_folders: non_empty(target.buildable_folders_hash),
      external: non_empty(target.external_hash)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
