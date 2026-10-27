defmodule Tuist.MCP.Components.Tools.OnceRunTools do
  @moduledoc false
  alias Tuist.MCP.Tool

  @nullable_string %{"type" => ["string", "null"]}
  @kinds ["build", "test", "generic"]

  def input(:list) do
    %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "kind" => %{"type" => "string", "enum" => @kinds, "description" => "Filter by run kind."},
        "status" => %{
          "type" => "string",
          "enum" => ["success", "failure"],
          "description" => "Filter by the result of finalized runs."
        },
        "is_ci" => %{"type" => "boolean", "description" => "Filter by whether the run happened on CI."},
        "git_branch" => %{"type" => "string", "description" => "Filter by git branch."},
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
        "run_id" => %{"type" => "string", "description" => "The Once run ID."}
      },
      "required" => ["account_handle", "project_handle", "run_id"]
    }
  end

  def output(:list) do
    object(%{
      "runs" => %{"type" => "array", "items" => run()},
      "pagination_metadata" => Tool.pagination_metadata_schema()
    })
  end

  def output(:get) do
    integers = &Map.new(&1, fn key -> {key, %{"type" => "integer"}} end)

    run()["properties"]
    |> Map.merge(%{
      "once_version" => @nullable_string,
      "git_dirty" => %{"type" => "boolean"},
      "exit_status" => %{"type" => ["integer", "null"]},
      "cancellation_reason" => @nullable_string,
      "actions" => object(integers.(~w(total cached executed failed))),
      "cache" =>
        ~w(hits misses total_lookups content_download_bytes content_upload_bytes content_saved_bytes)
        |> integers.()
        |> Map.put("hit_rate", %{"type" => ["number", "null"]})
        |> object(),
      "tests" =>
        ~w(test_cases passed failed skipped test_suites)
        |> integers.()
        |> object()
        |> Map.put("type", ["object", "null"])
    })
    |> object()
  end

  defp run do
    object(%{
      "run_id" => %{"type" => "string"},
      "kind" => %{"type" => "string", "enum" => @kinds},
      "command" => %{"type" => "string"},
      "status" => %{"type" => "string", "enum" => ["success", "failure", "in_progress"]},
      "duration_ms" => %{"type" => "integer"},
      "is_ci" => %{"type" => "boolean"},
      "git_rev" => @nullable_string,
      "git_branch" => @nullable_string,
      "host_class" => @nullable_string,
      "started_at" => @nullable_string,
      "finished_at" => @nullable_string,
      "cache" =>
        object(%{
          "hit_rate" => %{"type" => ["number", "null"]},
          "download_bytes" => %{"type" => "integer"},
          "upload_bytes" => %{"type" => "integer"}
        })
    })
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

defmodule Tuist.MCP.Components.Tools.ListOnceRuns do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_once_runs",
    title: "List Once Runs",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.OnceRunTools.input(:list),
    output_schema: Tuist.MCP.Components.Tools.OnceRunTools.output(:list)

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.OnceEvents.Query

  @impl EMCP.Tool
  def description,
    do:
      "List Once build, test and generic runs for a project, newest first. Runs that have not finalized have status in_progress."

  def execute(_conn, args, project) do
    {:ok,
     Query.list_runs(
       project.id,
       Map.merge(args, %{"page" => MCPTool.page(args), "page_size" => MCPTool.page_size(args)})
     )}
  end
end

defmodule Tuist.MCP.Components.Tools.GetOnceRun do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_once_run",
    title: "Get Once Run",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: Tuist.MCP.Components.Tools.OnceRunTools.input(:get),
    output_schema: Tuist.MCP.Components.Tools.OnceRunTools.output(:get)

  alias Tuist.OnceEvents.Query

  @impl EMCP.Tool
  def description,
    do:
      "Get a Once run with its action totals, cache summary and, for test runs, test totals. Run IDs are unique within a project."

  def execute(_conn, %{"run_id" => run_id}, project) do
    case Query.get_run(project.id, run_id) do
      {:ok, run} -> {:ok, run}
      {:error, :not_found} -> {:error, "Once run not found: #{run_id}"}
    end
  end
end
