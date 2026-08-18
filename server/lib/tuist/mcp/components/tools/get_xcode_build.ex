defmodule Tuist.MCP.Components.Tools.GetXcodeBuild do
  @moduledoc """
  Get detailed information about a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "get_xcode_build",
    title: "Get Xcode Build",
    read_only_hint: true,
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
        "id" => %{"type" => "string"},
        "duration" => %{"type" => "integer"},
        "status" => %{"type" => "string"},
        "category" => %{"type" => ["string", "null"]},
        "scheme" => %{"type" => "string"},
        "configuration" => %{"type" => "string"},
        "xcode_version" => %{"type" => "string"},
        "macos_version" => %{"type" => "string"},
        "model_identifier" => %{"type" => "string"},
        "is_ci" => %{"type" => "boolean"},
        "git_branch" => %{"type" => "string"},
        "git_commit_sha" => %{"type" => "string"},
        "git_ref" => %{"type" => "string"},
        "cacheable_tasks_count" => %{"type" => "integer"},
        "cacheable_task_local_hits_count" => %{"type" => "integer"},
        "cacheable_task_remote_hits_count" => %{"type" => "integer"},
        "inserted_at" => %{"type" => "string"},
        "archive_url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "duration",
        "status",
        "category",
        "scheme",
        "configuration",
        "xcode_version",
        "macos_version",
        "model_identifier",
        "is_ci",
        "git_branch",
        "git_commit_sha",
        "git_ref",
        "cacheable_tasks_count",
        "cacheable_task_local_hits_count",
        "cacheable_task_remote_hits_count",
        "inserted_at",
        "archive_url"
      ],
      "additionalProperties" => false
    }

  alias Tuist.Builds
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Storage

  # Shorter than the hour `list_test_case_run_attachments` hands out: this URL
  # rides along with build details the caller may only have wanted the metadata
  # from, so it lands in transcripts unasked-for and should stop working sooner.
  @archive_url_expires_in 900

  @impl EMCP.Tool
  def description,
    do:
      "Get detailed information about a specific build run, including a temporary download URL (valid for 15 minutes) " <>
        "for the archive it was processed from — a zip holding the raw .xcactivitylog, CAS metadata and machine " <>
        "metrics — for when the processed targets, files and issues are not enough. That URL is presigned and not " <>
        "checked for existence: a build whose archive was never uploaded, or has since been pruned, answers 404 on " <>
        "download. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  def execute(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, build, project} <-
           MCPTool.load_and_authorize(
             Builds.get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Build not found: #{build_run_id}"
           ) do
      {:ok,
       %{
         id: build.id,
         duration: build.duration,
         status: to_string(build.status),
         category: if(build.category != "", do: build.category),
         scheme: build.scheme,
         configuration: build.configuration,
         xcode_version: build.xcode_version,
         macos_version: build.macos_version,
         model_identifier: build.model_identifier,
         is_ci: build.is_ci,
         git_branch: build.git_branch,
         git_commit_sha: build.git_commit_sha,
         git_ref: build.git_ref,
         cacheable_tasks_count: build.cacheable_tasks_count,
         cacheable_task_local_hits_count: build.cacheable_task_local_hits_count,
         cacheable_task_remote_hits_count: build.cacheable_task_remote_hits_count,
         inserted_at: Formatter.iso8601(build.inserted_at, naive: :utc),
         archive_url: archive_url(build, project)
       }}
    end
  end

  # Signing is a local HMAC, so carrying the URL costs the caller nothing over
  # the build details they already asked for. Checking whether the archive is
  # really there would cost a storage round trip on every call, which is why the
  # description says a missing archive surfaces as a 404 on download instead.
  defp archive_url(build, project) do
    object_key = Builds.build_storage_key(project.account.name, project.name, build.id)

    Storage.generate_download_url(object_key, project.account,
      expires_in: @archive_url_expires_in,
      content_disposition: ~s(attachment; filename="#{Path.basename(object_key)}")
    )
  end
end
