defmodule Tuist.MCP.Components.Tools.GetBundleArtifactTree do
  @moduledoc """
  Get the full artifact tree for a bundle as a flat list sorted by path. The bundle_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/bundles/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Bundles
  alias Tuist.MCP.Components.ToolSupport

  @authorization_action :read
  @authorization_category :bundle

  @impl EMCP.Tool
  def name, do: "get_bundle_artifact_tree"

  @impl EMCP.Tool
  def description,
    do:
      "Get the full artifact tree for a bundle as a flat list sorted by path. The bundle_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/bundles/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "bundle_id" => %{
          "type" => "string",
          "description" => "The ID of the bundle."
        }
      },
      "required" => ["bundle_id"]
    }
  end

  @impl EMCP.Tool
  def call(conn, %{"bundle_id" => bundle_id}) do
    with {:ok, bundle} <-
           ToolSupport.load_resource(
             Bundles.get_bundle(bundle_id),
             "Bundle not found: #{bundle_id}"
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             conn.assigns,
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

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end
