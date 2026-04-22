defmodule Tuist.MCP.Components.Tools.ListTestCaseEvents do
  @moduledoc """
  List events for a test case (e.g. marked_flaky, quarantined, first_run). The test_case_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}.
  """

  use Tuist.MCP.Tool,
    name: "list_test_case_events",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_case_id" => %{
          "type" => "string",
          "description" => "The ID of the test case, or a Tuist dashboard URL."
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
      "required" => ["test_case_id"]
    }

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  @impl EMCP.Tool
  def description,
    do:
      "List events for a test case (e.g. marked_flaky, quarantined, first_run). The test_case_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}."

  @impl EMCP.Tool
  def call(conn, %{"test_case_id" => test_case_id} = args) when is_binary(test_case_id) do
    case MCPTool.load_and_authorize(
           Tests.get_test_case_by_id(test_case_id),
           conn.assigns,
           @authorization_action,
           @authorization_category,
           "Test case not found: #{test_case_id}"
         ) do
      {:ok, test_case, _project} ->
        page = MCPTool.page(args)
        page_size = MCPTool.page_size(args)
        {events, meta} = Tests.list_test_case_events(test_case.id, %{page: page, page_size: page_size})

        MCPTool.json_response(%{
          events:
            Enum.map(events, fn event ->
              %{
                event_type: event.event_type,
                inserted_at: Formatter.iso8601(event.inserted_at, naive: :utc),
                actor: if(event.actor, do: %{id: event.actor.id, name: event.actor.name})
              }
            end),
          pagination_metadata: MCPTool.pagination_metadata(meta)
        })

      {:error, message} ->
        EMCP.Tool.error(message)
    end
  end

  def call(_conn, _args) do
    EMCP.Tool.error("Provide a test_case_id.")
  end
end
