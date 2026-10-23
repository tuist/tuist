defmodule Atlas.MCP.Tools.GetErrorEventContextsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tools.GetErrorEventContexts
  alias Atlas.Repo

  setup :verify_on_exit!

  test "returns scoped tenant and flag observations without sensitive event payloads" do
    issue = insert_issue!()
    user = insert_user!(%{scopes: ["engineering:read"]})
    issue_id = issue.id

    expect(Errors, :list_events_for_issue, fn ^issue_id, [limit: 20] ->
      [
        %{
          event_id: "observed-event",
          timestamp: ~U[2026-10-23 10:00:00Z],
          environment: "production",
          release: "release-1",
          payload: %{
            "tags" => %{"feature_flag.runners" => "true", "selected_account_id" => "42", "token" => "secret"},
            "extra" => %{
              "selected_account_id" => 99,
              "selected_project_id" => 123,
              "selected_account_handle" => "customer",
              "request_body" => "private",
              "database_query" => %{"query" => "SELECT private"},
              "feature_flag.nested" => %{"credentials" => "private"},
              "feature_flag.oversized" => String.duplicate("x", 257)
            },
            "request" => %{"headers" => %{"Authorization" => "Bearer secret"}}
          }
        }
      ]
    end)

    assert {:ok, %{"service_project_id" => service_project_id, "event_contexts" => [event]}} =
             execute_tool(GetErrorEventContexts, mcp_conn(user), %{"id" => issue.id})

    assert service_project_id == issue.project_id

    assert event.context == %{
             "selected_account_id" => "42",
             "selected_project_id" => 123,
             "selected_account_handle" => "customer",
             "feature_flag.runners" => "true"
           }

    assert event.event_id == "observed-event"
    refute Map.has_key?(event, :payload)
  end

  test "event context requires engineering read before retrieving any issue or event" do
    user = insert_user!(%{scopes: []})
    reject(Errors, :fetch_issue, 1)
    reject(Errors, :list_events_for_issue, 2)

    assert {:error, _} =
             execute_tool(GetErrorEventContexts, mcp_conn(user), %{
               "id" => Ecto.UUID.generate()
             })
  end

  test "returns an error when the issue does not exist" do
    user = insert_user!(%{scopes: ["engineering:read"]})

    assert {:error, "Error issue not found."} =
             execute_tool(GetErrorEventContexts, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end

  defp insert_issue! do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    now = DateTime.truncate(DateTime.utc_now(), :microsecond)

    %Issue{}
    |> Issue.changeset(%{
      project_id: project.id,
      fingerprint: String.duplicate("a", 64),
      title: "Boom",
      first_seen: now,
      last_seen: now
    })
    |> Repo.insert!()
  end
end
