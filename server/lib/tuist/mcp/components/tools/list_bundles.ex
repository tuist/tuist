defmodule Tuist.MCP.Components.Tools.ListBundles do
  @moduledoc """
  List bundles (app binaries) for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.Bundles
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :bundle

  schema do
    field :account_handle, :string,
      required: true,
      description: "The account handle (organization or user)."

    field :project_handle, :string,
      required: true,
      description: "The project handle."

    field :git_branch, :string, description: "Filter by git branch."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(arguments, frame) do
    with {:ok, project} <-
           ToolSupport.resolve_and_authorize_project(
             arguments,
             frame,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)
      filters = build_filters(project.id, arguments)

      {bundles, meta} =
        Bundles.list_bundles(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
        bundles:
          Enum.map(bundles, fn bundle ->
            %{
              id: bundle.id,
              name: bundle.name,
              app_bundle_id: bundle.app_bundle_id,
              version: bundle.version,
              type: to_string(bundle.type),
              supported_platforms: bundle.supported_platforms || [],
              install_size: bundle.install_size,
              download_size: bundle.download_size,
              git_branch: bundle.git_branch,
              git_commit_sha: bundle.git_commit_sha,
              inserted_at: Formatter.iso8601(bundle.inserted_at)
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp build_filters(project_id, arguments) do
    base = [%{field: :project_id, op: :==, value: project_id}]

    case Map.get(arguments, :git_branch) do
      nil -> base
      value -> base ++ [%{field: :git_branch, op: :==, value: value}]
    end
  end
end
