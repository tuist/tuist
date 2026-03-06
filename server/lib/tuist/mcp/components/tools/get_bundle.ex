defmodule Tuist.MCP.Components.Tools.GetBundle do
  @moduledoc """
  Get detailed information about a specific bundle. Use list_bundle_artifacts to drill into the artifact tree. The bundle_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/bundles/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.Bundles
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter

  @authorization_action :read
  @authorization_category :bundle

  schema do
    field :bundle_id, :string,
      required: true,
      description: "The ID of the bundle."
  end

  @impl true
  def execute(%{bundle_id: bundle_id}, frame) do
    with {:ok, bundle} <-
           ToolSupport.load_resource(
             Bundles.get_bundle(bundle_id),
             "Bundle not found: #{bundle_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             bundle.project_id,
             @authorization_action,
             @authorization_category
           ) do
      data = %{
        id: bundle.id,
        name: bundle.name,
        app_bundle_id: bundle.app_bundle_id,
        version: bundle.version,
        type: to_string(bundle.type),
        supported_platforms: Enum.map(bundle.supported_platforms || [], &to_string/1),
        install_size: bundle.install_size,
        download_size: bundle.download_size,
        git_branch: bundle.git_branch,
        git_commit_sha: bundle.git_commit_sha,
        git_ref: bundle.git_ref,
        inserted_at: Formatter.iso8601(bundle.inserted_at)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end
end
