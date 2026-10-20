defmodule Tuist.MCP.Components.Tools.MixBuildTools do
  @moduledoc false
  alias Tuist.MCP.Tool

  @nullable_string %{"type" => ["string", "null"]}
  @nullable_number %{"type" => ["number", "null"]}
  @nullable_integer %{"type" => ["integer", "null"]}
  @strings ~w(elixir_version otp_version mix_env git_branch git_commit_sha git_ref ci_provider ci_run_id ci_project_handle ci_host)
  @durations ~w(avg_read_duration_us p50_read_duration_us p90_read_duration_us p99_read_duration_us avg_write_duration_us p50_write_duration_us p90_write_duration_us p99_write_duration_us)

  def input(:list) do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "git_branch" => %{"type" => "string", "description" => "Filter by git branch."},
        "status" => %{"type" => "string", "enum" => ["success", "failure"], "description" => "Filter by status."},
        "is_ci" => %{"type" => "boolean", "description" => "Filter by whether the build ran on CI."},
        "mix_env" => %{"type" => "string", "description" => "Filter by Mix environment, for example dev or test."},
        "page" => %{"type" => "integer", "minimum" => 1, "description" => "Page number (default: 1)."},
        "page_size" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Results per page (default: 20, max: 100)."
        }
      },
      "required" => ["account_handle", "project_handle"]
    }
  end

  def input(:get) do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "build_id" => %{"type" => "string", "description" => "The Mix build ID."}
      },
      "required" => ["account_handle", "project_handle", "build_id"]
    }
  end

  def output(:list) do
    object(%{
      "builds" => %{"type" => "array", "items" => build()},
      "pagination_metadata" => Tool.pagination_metadata_schema()
    })
  end

  def output(:get) do
    cache =
      @durations
      |> Map.new(&{&1, @nullable_number})
      |> Map.merge(%{
        "hits" => %{"type" => "integer"},
        "local_hits" => %{"type" => "integer"},
        "remote_hits" => %{"type" => "integer"},
        "misses" => %{"type" => "integer"},
        "bypasses" => %{"type" => "integer"},
        "hit_rate" => @nullable_number,
        "saved_duration_ms" => @nullable_integer,
        "read_bytes" => @nullable_integer,
        "write_bytes" => @nullable_integer
      })
      |> object()

    object(Map.put(build()["properties"], "cache", cache))
  end

  defp build do
    @strings
    |> Map.new(&{&1, @nullable_string})
    |> Map.merge(%{
      "id" => %{"type" => "string"},
      "actor" => Tool.report_actor_schema(),
      "status" => %{"type" => "string", "enum" => ["success", "failure"]},
      "duration_ms" => %{"type" => "integer"},
      "is_ci" => %{"type" => "boolean"},
      "custom_metadata" =>
        object(%{
          "tags" => %{"type" => "array", "items" => %{"type" => "string"}},
          "values" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}}
        }),
      "diagnostics_error_count" => %{"type" => "integer"},
      "diagnostics_warning_count" => %{"type" => "integer"},
      "started_at" => @nullable_string,
      "inserted_at" => %{"type" => "string"}
    })
    |> object()
  end

  defp object(properties) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" => properties |> Map.keys() |> Enum.sort(),
      "additionalProperties" => false
    }
  end
end

defmodule Tuist.MCP.Components.Tools.ListMixBuilds do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_mix_builds",
    title: "List Mix Builds",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.MixBuildTools.input(:list),
    output_schema: Tuist.MCP.Components.Tools.MixBuildTools.output(:list)

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Mix.Query

  @impl EMCP.Tool
  def description, do: "List Mix (Elixir) compile builds for a project, newest first, including custom metadata."

  def execute(_conn, args, project) do
    {:ok,
     Query.list_builds(
       project.id,
       Map.merge(args, %{"page" => MCPTool.page(args), "page_size" => MCPTool.page_size(args)})
     )}
  end
end

defmodule Tuist.MCP.Components.Tools.GetMixBuild do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_mix_build",
    title: "Get Mix Build",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.MixBuildTools.input(:get),
    output_schema: Tuist.MCP.Components.Tools.MixBuildTools.output(:get)

  alias Tuist.Mix.Query

  @impl EMCP.Tool
  def description,
    do:
      "Get a Mix (Elixir) compile build with diagnostics counts and its dependency cache summary. Saved duration estimates avoided compilation, not elapsed build savings. Build IDs are unique within a project."

  def execute(_conn, %{"build_id" => build_id}, project) do
    case Query.get_build(project.id, build_id) do
      {:ok, build} -> {:ok, build}
      {:error, :not_found} -> {:error, "Mix build not found: #{build_id}"}
    end
  end
end
