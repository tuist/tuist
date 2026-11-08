defmodule Atlas.MCP.Tools.RequestClusterElevationTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.MCP
  alias Atlas.MCP.Tools.RequestClusterElevation
  alias Atlas.TuistOps

  setup :verify_on_exit!

  @moduletag :tmp_dir

  @elevation %{
    "env" => "canary",
    "thread_id" => "T-01a1a731-7e97-70e1-8d68-468b02fbb096",
    "intent" => "Uncordon tuist-tuist-ovh-fleet-runners-linux-gnbmk-jgl25",
    "duration_minutes" => 30
  }

  setup %{tmp_dir: tmp_dir} do
    token_path = Path.join(tmp_dir, "token")
    File.write!(token_path, "atlas-ops-token\n")
    stub(TuistOps, :config, fn -> [base_url: "https://ops.example", token_path: token_path] end)
    :ok
  end

  test "grants the thread as the caller only after they approve that exact call" do
    owner = insert_user!()
    tuist_ops()

    assert {:error, message} = RequestClusterElevation.execute(agent_conn(owner), @elevation)
    assert [%{id: id, server_name: "tuist-ops"}] = MCP.list_pending_tool_approvals(owner)
    assert message =~ "/admin/mcps#mcp-approval-#{id}"
    refute_received {:grant, _}

    assert {:ok, _} = MCP.decide_tool_approval(owner, id, "approved")

    assert {:ok, %{env: "canary", thread_id: "T-01a1a731-7e97-70e1-8d68-468b02fbb096"}} =
             RequestClusterElevation.execute(agent_conn(owner), @elevation)

    assert_received {:grant, body}

    assert body == %{
             "email" => owner.email,
             "env" => "canary",
             "thread_id" => @elevation["thread_id"],
             "intent" => @elevation["intent"],
             "ttl_seconds" => 1800,
             "approval_id" => id
           }

    # The approval is spent: a longer elevation, or the same one again, needs a new one.
    assert {:error, _} = RequestClusterElevation.execute(agent_conn(owner), %{@elevation | "duration_minutes" => 60})
    assert {:error, _} = RequestClusterElevation.execute(agent_conn(owner), @elevation)
    refute_received {:grant, _}
  end

  test "another person's approval does not grant the caller's call" do
    owner = insert_user!()
    other = insert_user!()
    tuist_ops()

    assert {:error, _} = RequestClusterElevation.execute(agent_conn(other), @elevation)
    [%{id: id}] = MCP.list_pending_tool_approvals(other)
    {:ok, _} = MCP.decide_tool_approval(other, id, "approved")

    assert {:error, _} = RequestClusterElevation.execute(agent_conn(owner), @elevation)
    refute_received {:grant, _}
  end

  test "reports a refusal from tuist-ops instead of claiming the grant" do
    owner = insert_user!()

    stub_http(fn conn ->
      conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{"error" => "no engineering tailnet role"})
    end)

    approve_next!(owner)

    assert {:error, message} = RequestClusterElevation.execute(agent_conn(owner), @elevation)
    assert message =~ "HTTP 403"
    assert message =~ "no engineering tailnet role"
  end

  test "files no approval when this environment cannot reach tuist-ops" do
    owner = insert_user!()
    stub(TuistOps, :config, fn -> [base_url: "https://ops.example", token_path: "/nonexistent/token"] end)

    assert {:error, message} = RequestClusterElevation.execute(agent_conn(owner), @elevation)
    assert message =~ "not configured"
    assert MCP.list_pending_tool_approvals(owner) == []
  end

  test "callers that act as a fixed operator cannot elevate" do
    user = insert_user!()

    assert {:error, message} =
             RequestClusterElevation.execute(%{assigns: %{current_user: user, audit_interface: "slack"}}, @elevation)

    assert message =~ "only callable over Atlas MCP"
    assert MCP.list_pending_tool_approvals(user) == []
  end

  test "rejects staging and durations past an hour before filing anything" do
    owner = insert_user!()

    assert {:error, _} = RequestClusterElevation.execute(agent_conn(owner), %{@elevation | "env" => "staging"})

    assert {:error, _} =
             RequestClusterElevation.execute(agent_conn(owner), %{@elevation | "duration_minutes" => 61})

    assert MCP.list_pending_tool_approvals(owner) == []
  end

  defp agent_conn(user), do: %{assigns: %{current_user: user, audit_interface: "mcp"}}

  defp approve_next!(owner) do
    assert {:error, _} = RequestClusterElevation.execute(agent_conn(owner), @elevation)
    [%{id: id}] = MCP.list_pending_tool_approvals(owner)
    {:ok, _} = MCP.decide_tool_approval(owner, id, "approved")
  end

  # A fake of tuist-ops' grant endpoint that records what Atlas sent.
  defp tuist_ops do
    stub_http(fn conn ->
      assert {"POST", "/api/v1/atlas/elevations"} == {conn.method, conn.request_path}
      assert ["Bearer atlas-ops-token"] == Plug.Conn.get_req_header(conn, "authorization")
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = JSON.decode!(body)
      send(self(), {:grant, body})

      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "elevation_id" => 1,
        "env" => body["env"],
        "thread_id" => body["thread_id"],
        "expires_at" => "2026-11-08T19:30:00Z"
      })
    end)
  end

  defp stub_http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
