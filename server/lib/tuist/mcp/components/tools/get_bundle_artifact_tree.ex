defmodule Tuist.MCP.Components.Tools.GetBundleArtifactTree do
  @moduledoc """
  Get the full artifact tree for a bundle as a flat list sorted by path. The bundle_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/bundles/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.Bundles
  alias Tuist.MCP.Components.ToolSupport

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
      artifacts = Bundles.get_bundle_artifact_tree(bundle_id)

      data = %{
        bundle_id: bundle_id,
        artifacts:
          Enum.map(artifacts, fn artifact ->
            %{
              artifact_type: to_string(artifact.artifact_type),
              path: artifact.path,
              size: artifact.size
            }
          end)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end
end
