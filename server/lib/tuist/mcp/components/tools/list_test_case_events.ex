defmodule Tuist.MCP.Components.Tools.ListTestCaseEvents do
  @moduledoc """
  List events for a test case (e.g. marked_flaky, quarantined, first_run). The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_test_case_events",
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "test_case_id" => %{
          "type" => "string",
          "description" => "The ID of the test case."
        },
        "page" => %{
          "type" => "integer",
          "description" => "Page number (default: 1)."
        },
        "page_size" => %{
          "type" => "integer",
          "description" => "Results per page (default: 20, max: 100)."
        }
      },
      "required" => ["account_handle", "project_handle", "test_case_id"]
    }

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @impl EMCP.Tool
  def description,
    do:
      "List events for a test case (e.g. marked_flaky, quarantined, first_run). The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    test_case_id = Map.fetch!(args, "test_case_id")
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)

    case Tests.get_test_case_by_id(test_case_id) do
      {:ok, test_case} ->
        if test_case.project_id == project.id do
          {events, meta} = Tests.list_test_case_events(test_case_id, %{page: page, page_size: page_size})

          {:ok,
           %{
             events:
               Enum.map(events, fn event ->
                 %{
                   event_type: event.event_type,
                   inserted_at: Formatter.iso8601(event.inserted_at, naive: :utc),
                   actor: if(event.actor, do: %{id: event.actor.id, name: event.actor.name})
                 }
               end),
             pagination_metadata: MCPTool.pagination_metadata(meta)
           }}
        else
          {:error, "Test case not found: #{test_case_id}"}
        end

      {:error, :not_found} ->
        {:error, "Test case not found: #{test_case_id}"}
    end
  end
end
