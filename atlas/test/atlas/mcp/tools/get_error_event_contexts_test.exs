defmodule Atlas.MCP.Tools.GetErrorEventContextsTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Issue
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.GetErrorEventContexts
  alias Atlas.Repo

  setup :verify_on_exit!

  for {label, args} <- [
        {"missing ID", %{}},
        {"integer ID", %{"id" => 42}},
        {"null ID", %{"id" => nil}},
        {"object ID", %{"id" => %{}}},
        {"array ID", %{"id" => []}},
        {"invalid UUID", %{"id" => "not-a-uuid"}},
        {"additional properties", %{"id" => "00000000-0000-0000-0000-000000000000", "extra" => true}}
      ] do
    test "MCP dispatch rejects #{label} before retrieving any issue or event" do
      user = insert_user!(%{scopes: ["engineering:read"]})
      reject(Errors, :fetch_issue, 1)
      reject(Errors, :list_events_for_issue, 2)

      response = dispatch_tool(user, unquote(Macro.escape(args)))

      assert response["result"]["isError"] == true

      assert [%{"type" => "text", "text" => message}] = response["result"]["content"]
      assert message == "Arguments do not match the error event context tool schema."
    end
  end

  test "returns scoped tenant and flag observations without sensitive event payloads" do
    issue = insert_issue!()
    user = insert_user!(%{scopes: ["engineering:read"]})
    issue_id = issue.id

    event = %{
      event_id: "observed-event",
      timestamp: ~U[2026-10-23 10:00:00Z],
      environment: "production",
      release: "release-1",
      payload: %{
        "tags" => %{
          "feature_flag.runners" => "true",
          "feature_flag.enabled" => false,
          "feature_flag.revision" => 3,
          "selected_account_id" => "42",
          "token" => "secret",
          "feature_flag.nested_tag" => %{"credentials" => "private"},
          "feature_flag.list_tag" => ["private"],
          "feature_flag.float_tag" => 0.5,
          "feature_flag.null_tag" => nil,
          "feature_flag.oversized_tag" => String.duplicate("x", 257),
          ("feature_flag." <> String.duplicate("k", 115)) => String.duplicate("x", 256),
          ("feature_flag." <> String.duplicate("k", 116)) => "private"
        },
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

    tag_pairs =
      Enum.map(event.payload["tags"], fn {key, value} -> [key, value] end) ++
        [
          [],
          ["feature_flag.missing"],
          ["feature_flag.too_many", "private", "private"],
          [42, "private"],
          [%{"private" => true}, "private"],
          %{"feature_flag.object" => "private"},
          "private",
          nil
        ]

    [map_result, pair_result] =
      for tags <- [event.payload["tags"], tag_pairs] do
        expect(Errors, :list_events_for_issue, fn ^issue_id, [limit: 20] ->
          [put_in(event.payload["tags"], tags)]
        end)

        response = dispatch_tool(user, %{"id" => issue.id})
        refute response["result"]["isError"]
        response["result"]["structuredContent"]
      end

    assert pair_result == map_result
    assert map_result["service_project_id"] == issue.project_id
    assert [context] = map_result["event_contexts"]

    assert context["context"] == %{
             "selected_account_id" => "42",
             "selected_project_id" => 123,
             "selected_account_handle" => "customer",
             "feature_flag.runners" => "true",
             "feature_flag.enabled" => false,
             "feature_flag.revision" => 3,
             ("feature_flag." <> String.duplicate("k", 115)) => String.duplicate("x", 256)
           }

    assert context["event_id"] == "observed-event"
    refute Map.has_key?(context, "payload")
  end

  test "map and pair-list tags retain the same 64-field limit without accepting pair-list extras" do
    issue = insert_issue!()
    user = insert_user!(%{scopes: ["engineering:read"]})
    issue_id = issue.id
    tags = Map.new(1..70, &{"feature_flag.flag_#{&1}", true})

    expect(Errors, :list_events_for_issue, fn ^issue_id, [limit: 20] ->
      for representation <- [tags, Enum.map(tags, fn {key, value} -> [key, value] end)] do
        %{
          event_id: "bounded-event",
          timestamp: ~U[2026-10-23 10:00:00Z],
          environment: "production",
          release: "release-1",
          payload: %{
            "tags" => representation,
            "extra" => [["feature_flag.private_extra", "private"]]
          }
        }
      end
    end)

    response = dispatch_tool(user, %{"id" => issue.id})
    assert [map_event, pair_event] = response["result"]["structuredContent"]["event_contexts"]
    assert pair_event == map_event
    assert map_size(map_event["context"]) == 64

    assert map_event["context"] == tags |> Enum.sort_by(&elem(&1, 0)) |> Enum.take(64) |> Map.new()
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

  test "MCP dispatch retains engineering scope and production-systems group restrictions" do
    reject(Errors, :fetch_issue, 1)
    reject(Errors, :list_events_for_issue, 2)

    for {scopes, groups} <- [{[], ["observability"]}, {["engineering:read"], []}] do
      user = insert_user!(%{scopes: scopes})
      conn = %{assigns: %{current_user: user, mcp_claims: %{"mcp_tool_groups" => groups}}}

      response =
        Server.handle_message(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => GetErrorEventContexts.name(), "arguments" => %{"id" => Ecto.UUID.generate()}}
        })

      assert response["error"]["message"] =~ "not available"
    end
  end

  test "returns an error when the issue does not exist" do
    user = insert_user!(%{scopes: ["engineering:read"]})

    assert {:error, "Error issue not found."} =
             execute_tool(GetErrorEventContexts, mcp_conn(user), %{
               "id" => "00000000-0000-0000-0000-000000000000"
             })
  end

  defp dispatch_tool(user, args) do
    conn = %{assigns: %{current_user: user, mcp_claims: %{"mcp_tool_groups" => ["observability"]}}}

    Server.handle_message(conn, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => GetErrorEventContexts.name(), "arguments" => args}
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
