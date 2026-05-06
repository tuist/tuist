defmodule Tuist.MCP.Components.Tools.GetBundle do
  @moduledoc """
  Get detailed information about a specific bundle. Use get_bundle_artifact_tree to get the full artifact list. The bundle_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/bundles/{id}.
  """

  use Tuist.MCP.Tool,
    name: "get_bundle",
    title: "Get App Bundle",
    schema: %{
      "type" => "object",
      "properties" => %{
        "bundle_id" => %{
          "type" => "string",
          "description" => "The ID of the bundle."
        }
      },
      "required" => ["bundle_id"]
    }

  alias Tuist.Bundles
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific bundle. Use get_bundle_artifact_tree to get the full artifact list. The bundle_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/bundles/{id}."

  def execute(conn, %{"bundle_id" => bundle_id}) do
    with {:ok, bundle, _project} <-
           MCPTool.load_and_authorize(
             Bundles.get_bundle(bundle_id),
             conn.assigns,
             :read,
             :bundle,
             "Bundle not found: #{bundle_id}"
           ) do
      {:ok,
       %{
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
       }}
    end
  end
end
