defmodule AtlasWeb.SupportAgentFeedbackControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Repo
  alias Atlas.Support
  alias Atlas.Support.Thread

  @token "tuist-server-token"
  @body %{
    "name" => "Maya Chen",
    "email" => "maya@customer.example",
    "body" => "Expected: test runs filtered by branch\n\nActual: the branch was ignored",
    "context" => %{"tool_name" => "list_test_runs", "category" => "missing_data"}
  }

  setup :verify_on_exit!

  test "opens a support conversation for an authenticated report", %{conn: conn} do
    stub(Support, :ingest_token, fn -> @token end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/support/agent-feedback", @body)

    assert %{"id" => id} = json_response(conn, 201)
    thread = Repo.get!(Thread, id)
    assert thread.customer_email == "maya@customer.example"
    assert thread.metadata["channel"] == "agent_feedback"
  end

  test "rejects an invalid token", %{conn: conn} do
    stub(Support, :ingest_token, fn -> @token end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong")
      |> post(~p"/api/support/agent-feedback", @body)

    assert %{"error" => "invalid token"} = json_response(conn, 401)
    assert Repo.aggregate(Thread, :count) == 0
  end

  test "stays closed when no token is configured", %{conn: conn} do
    stub(Support, :ingest_token, fn -> nil end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer anything")
      |> post(~p"/api/support/agent-feedback", @body)

    assert %{"error" => "not configured"} = json_response(conn, 401)
  end

  test "limits how many reports one user's agents can open", %{conn: conn} do
    stub(Support, :ingest_token, fn -> @token end)
    body = Map.put(@body, "email", "looping-#{System.unique_integer([:positive])}@customer.example")

    statuses =
      for _attempt <- 1..11 do
        conn
        |> put_req_header("authorization", "Bearer " <> @token)
        |> post(~p"/api/support/agent-feedback", body)
        |> Map.fetch!(:status)
      end

    assert Enum.count(statuses, &(&1 == 201)) == 10
    assert List.last(statuses) == 429
  end

  test "rejects a report without an email", %{conn: conn} do
    stub(Support, :ingest_token, fn -> @token end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> @token)
      |> post(~p"/api/support/agent-feedback", Map.delete(@body, "email"))

    assert %{"error" => "email_required"} = json_response(conn, 422)
  end
end
