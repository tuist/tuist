defmodule Tuist.MCP.Components.Tools.GetXcodeBuildArchive do
  @moduledoc """
  Get a temporary download URL for a build run's uploaded archive, which holds
  the `.xcactivitylog` the build was processed from.
  """

  use Tuist.MCP.Tool,
    name: "get_xcode_build_archive",
    title: "Get Xcode Build Archive",
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        }
      },
      "required" => ["build_run_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{"type" => "string"},
        "archive" => Tuist.MCP.ArtifactDownload.schema(true)
      },
      "required" => ["build_run_id", "archive"],
      "additionalProperties" => false
    }

  alias Tuist.Builds
  alias Tuist.MCP.ArtifactDownload
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get a temporary download URL (valid for 1 hour) for a build run's uploaded archive — a zip holding the " <>
        "raw .xcactivitylog, CAS metadata and machine metrics the build was processed from. Use it when the " <>
        "processed build data (targets, files, issues) is not enough and you need the log Xcode actually emitted. " <>
        "Null when the archive was never uploaded or has since been pruned."

  def execute(conn, %{"build_run_id" => build_run_id}) when is_binary(build_run_id) do
    with {:ok, build, project} <-
           MCPTool.load_and_authorize(
             Builds.get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Build not found: #{build_run_id}"
           ),
         object_key = Builds.build_storage_key(project.account.name, project.name, build.id),
         {:ok, archive} <- ArtifactDownload.presign_optional(object_key, project.account) do
      {:ok, %{build_run_id: build_run_id, archive: archive}}
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, _reason} -> {:error, "Could not reach artifact storage."}
    end
  end

  def execute(_conn, _args), do: {:error, "build_run_id is required and must be a string."}
end
