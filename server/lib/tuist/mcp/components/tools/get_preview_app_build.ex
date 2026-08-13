defmodule Tuist.MCP.Components.Tools.GetPreviewAppBuild do
  @moduledoc """
  Get a temporary download URL for a preview's app build (an `.ipa`, `.apk`, or
  zipped app bundle).
  """

  use Tuist.MCP.Tool,
    name: "get_preview_app_build",
    title: "Get Preview App Build",
    schema: %{
      "type" => "object",
      "properties" => %{
        "app_build_id" => %{
          "type" => "string",
          "description" => "The ID of the app build, as found on a preview."
        }
      },
      "required" => ["app_build_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "app_build_id" => %{"type" => "string"},
        "preview_id" => %{"type" => "string"},
        "type" => %{"type" => "string"},
        "supported_platforms" => %{"type" => "array", "items" => %{"type" => "string"}},
        "build" => Tuist.MCP.ArtifactDownload.schema(true)
      },
      "required" => ["app_build_id", "preview_id", "type", "supported_platforms", "build"],
      "additionalProperties" => false
    }

  alias Tuist.AppBuilds
  alias Tuist.MCP.ArtifactDownload
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get a temporary download URL (valid for 1 hour) for a preview's app build — the .ipa, .apk, or zipped app " <>
        "bundle that was uploaded. Null when the binary was never uploaded or has since been pruned."

  def execute(conn, %{"app_build_id" => app_build_id}) when is_binary(app_build_id) do
    with {:ok, app_build} <- app_build(app_build_id),
         {:ok, _preview, project} <-
           MCPTool.load_and_authorize(
             {:ok, app_build.preview},
             conn.assigns,
             :read,
             :preview,
             "App build not found: #{app_build_id}"
           ),
         object_key =
           AppBuilds.storage_key(%{
             account_handle: project.account.name,
             project_handle: project.name,
             app_build: app_build
           }),
         {:ok, build} <- ArtifactDownload.presign_optional(object_key, project.account) do
      {:ok,
       %{
         app_build_id: app_build.id,
         preview_id: app_build.preview_id,
         type: to_string(app_build.type),
         supported_platforms: Enum.map(app_build.supported_platforms || [], &to_string/1),
         build: build
       }}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "Could not reach artifact storage."}
    end
  end

  def execute(_conn, _args), do: {:error, "app_build_id is required and must be a string."}

  # `app_build_by_id/2` answers a malformed id with its own message; the caller
  # only needs to know nothing was found.
  defp app_build(app_build_id) do
    case AppBuilds.app_build_by_id(app_build_id, preload: [:preview]) do
      {:ok, %{preview: %{}} = app_build} -> {:ok, app_build}
      _other -> {:error, "App build not found: #{app_build_id}"}
    end
  end
end
