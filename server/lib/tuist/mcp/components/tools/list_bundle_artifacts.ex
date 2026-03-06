defmodule Tuist.MCP.Components.Tools.ListBundleArtifacts do
  @moduledoc """
  List artifacts for a bundle. Use parent_artifact_id to drill into nested artifacts. The bundle_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/bundles/{id}.
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

    field :parent_artifact_id, :string,
      description:
        "The ID of a parent artifact to list children of. " <>
          "Omit to list top-level artifacts."
  end

  @impl true
  def execute(%{bundle_id: bundle_id} = arguments, frame) do
    parent_artifact_id = Map.get(arguments, :parent_artifact_id)

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
      opts = if parent_artifact_id, do: [parent_artifact_id: parent_artifact_id], else: []
      artifacts = Bundles.list_bundle_artifacts(bundle_id, opts)

      data = %{
        bundle_id: bundle_id,
        parent_artifact_id: parent_artifact_id,
        artifacts:
          Enum.map(artifacts, fn artifact ->
            %{
              id: artifact.id,
              artifact_type: to_string(artifact.artifact_type),
              path: artifact.path,
              size: artifact.size,
              shasum: artifact.shasum,
              has_children: artifact.artifact_type == :directory
            }
          end)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end
end
