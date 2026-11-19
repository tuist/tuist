defmodule Atlas.MCP.Tools.ListOVHInvoicesTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Proxy.Server
  alias Atlas.MCP.Tools.ListOVHInvoices

  setup :verify_on_exit!

  test "lists IDs with inclusive date bounds normalized to UTC" do
    user = insert_user!(%{scopes: ["finance:read"]})

    stub(Proxy, :fetch_server, fn "ovh-orders" ->
      {:ok, %Server{name: "ovh-orders", url: "https://mcp.ovh.example/mcp/v1_me", auth_type: :oauth2}}
    end)

    expect(MCP, :access_token_for, fn ^user, _server -> {:ok, "own-token"} end)

    expect(Req, :request, fn opts ->
      assert opts[:url] == "https://api.us.ovhcloud.com/1.0/me/bill"
      assert opts[:auth] == {:bearer, "own-token"}
      assert opts[:redirect] == false
      assert Map.new(opts[:params]) == %{"date.from" => "2026-11-01T00:00:00Z", "date.to" => "2026-11-12T23:59:59Z"}
      {:ok, %Req.Response{status: 200, body: ["INV_US1234567", "INV_US2345678"]}}
    end)

    assert {:ok, %{invoice_ids: ["INV_US1234567", "INV_US2345678"]}} =
             execute_tool(ListOVHInvoices, mcp_conn(user), %{
               "date_from" => "2026-11-01T01:00:00+01:00",
               "date_to" => "2026-11-12T23:59:59Z"
             })

    assert %{metadata: %{"count" => 2}} = Repo.get_by!(Activity, action: "ovh.invoices_listed", actor_id: user.id)
  end

  test "rejects invalid and inverted dates and callers without finance access" do
    conn = executive_mcp_conn()
    reject(Req, :request, 1)

    for args <- [
          %{"date_from" => "2026-11-01"},
          %{"date_from" => "2026-11-12T00:00:00Z", "date_to" => "2026-11-01T00:00:00Z"}
        ] do
      assert {:error, message} = execute_tool(ListOVHInvoices, conn, args)
      assert message =~ "ISO-8601"
    end

    assert {:error, message} = execute_tool(ListOVHInvoices, mcp_conn(insert_user!()), %{})
    assert message =~ "finance:read"
  end
end
