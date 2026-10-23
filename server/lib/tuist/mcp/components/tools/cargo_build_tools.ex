defmodule Tuist.MCP.Components.Tools.CargoBuildTools do
  @moduledoc false
  alias Tuist.Cargo.CacheMetrics
  alias Tuist.MCP.Tool

  @nullable_string %{"type" => ["string", "null"]}
  @strings ~w(command rust_version git_branch git_commit_sha git_ref ci_provider ci_run_id ci_project_handle ci_host)

  def input(:list) do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "git_branch" => %{"type" => "string", "description" => "Filter by git branch."},
        "status" => %{"type" => "string", "enum" => ["success", "failure"], "description" => "Filter by status."},
        "is_ci" => %{"type" => "boolean", "description" => "Filter by whether the build ran on CI."},
        "command" => %{"type" => "string", "description" => "Filter by Cargo subcommand, for example build or check."},
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
        "build_id" => %{"type" => "string", "description" => "The Cargo build ID."}
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
      CacheMetrics.counters()
      |> Map.new(&{Atom.to_string(&1), %{"type" => "integer"}})
      |> Map.merge(%{"task_misses" => %{"type" => "integer"}, "hit_rate" => %{"type" => ["number", "null"]}})
      |> object()
      |> Map.put("type", ["object", "null"])

    build = build()
    object(Map.put(build["properties"], "cache", cache))
  end

  defp build do
    @strings
    |> Map.new(&{&1, @nullable_string})
    |> Map.merge(%{
      "id" => %{"type" => "string"},
      "actor" => Tool.report_actor_schema(),
      "custom_metadata" =>
        object(%{
          "tags" => %{"type" => "array", "items" => %{"type" => "string"}},
          "values" => %{"type" => "object", "additionalProperties" => %{"type" => "string"}}
        }),
      "status" => %{"type" => "string", "enum" => ["success", "failure"]},
      "duration_ms" => %{"type" => "integer"},
      "is_ci" => %{"type" => "boolean"},
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

defmodule Tuist.MCP.Components.Tools.ListCargoBuilds do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_cargo_builds",
    title: "List Cargo Builds",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.CargoBuildTools.input(:list),
    output_schema: Tuist.MCP.Components.Tools.CargoBuildTools.output(:list)

  alias Tuist.Cargo.Query
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List Cargo builds for a project, newest first. Cargo test runs reported as nextest are not builds and are not listed."

  def execute(_conn, args, project) do
    {:ok,
     Query.list_builds(
       project.id,
       Map.merge(args, %{"page" => MCPTool.page(args), "page_size" => MCPTool.page_size(args)})
     )}
  end
end

defmodule Tuist.MCP.Components.Tools.GetCargoBuild do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_cargo_build",
    title: "Get Cargo Build",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.CargoBuildTools.input(:get),
    output_schema: Tuist.MCP.Components.Tools.CargoBuildTools.output(:get)

  alias Tuist.Cargo.Query

  @impl EMCP.Tool
  def description,
    do:
      "Get a Cargo build with its aggregate cache counters. Estimated avoided compiler time is not wall-clock savings. Build IDs are unique within a project."

  def execute(_conn, %{"build_id" => build_id}, project) do
    case Query.get_build(project.id, build_id) do
      {:ok, build} -> {:ok, build}
      {:error, :not_found} -> {:error, "Cargo build not found: #{build_id}"}
    end
  end
end
