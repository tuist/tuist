defmodule Atlas.MCP.Tools.SaveOVHInvoiceTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Automations.DomainRegistry
  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.MCP.OAuthSession
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Proxy.Config
  alias Atlas.MCP.Proxy.Server, as: UpstreamServer
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.ListOVHInvoices
  alias Atlas.MCP.Tools.SaveOVHInvoice
  alias Atlas.Moodboard.SafeHTTP
  alias Atlas.Orbit.ToolPolicy
  alias Atlas.TestSupport.Documents.Storage

  setup :verify_on_exit!

  setup do
    stub(Config, :get, fn ->
      [servers: [%{"name" => "ovh-orders", "url" => "https://mcp.ovh.example/mcp/v1_me", "auth_type" => "oauth2"}]]
    end)

    user = insert_user!(%{scopes: ["finance:read", "documents:write"]})
    connect!(user, "own-token")
    %{user: user, conn: mcp_conn(user)}
  end

  test "saves invoice bytes and gross currency amount using only the caller's connection", %{user: user, conn: conn} do
    connect!(insert_user!(), "another-person-token")
    invoice_api()
    pdf = "%PDF-1.7\ninvoice bytes"

    expect(SafeHTTP, :fetch, fn "https://download.ovh.example/invoice?signed=secret" ->
      {:ok, %{status: 200, body: pdf}}
    end)

    assert {:ok, result} = execute_tool(SaveOVHInvoice, conn, %{"invoice_id" => "INV_US1234567"})
    assert %{invoice_id: "INV_US1234567", amount: "151.61", currency: "USD", date: "2026-11-05T09:43:00Z"} = result
    assert result.filename == "INV_US1234567.pdf"
    assert result.content_type == "application/pdf"
    assert result.byte_size == byte_size(pdf)

    document = Documents.get_document(result.document_id)
    assert document.uploaded_by_id == user.id
    assert document.attributes == %{"provider" => "ovh", "invoice_id" => "INV_US1234567"}
    assert {:ok, %{body: ^pdf}} = Storage.get_object(document.storage_key)
    assert Repo.get_by(Activity, action: "ovh.invoice_saved", actor_id: user.id, target_id: document.id)
    refute JSON.encode!(result) =~ "secret"
    refute JSON.encode!(document.attributes) =~ "password"
  end

  test "rejects unsafe links and login pages without creating a document", %{conn: conn} do
    invoice_api()

    for download <- [{:error, :unsafe_url}, {:ok, %{status: 200, body: "<html>Sign in</html>"}}] do
      expect(SafeHTTP, :fetch, fn _url -> download end)
      assert {:error, message} = execute_tool(SaveOVHInvoice, conn, %{"invoice_id" => "INV_US1234567"})
      assert message =~ "No document was saved"
      refute Repo.exists?(Document)
    end
  end

  test "does not leak rejected provider bodies or use someone else's grant", %{conn: conn} do
    stub_http(fn conn -> Plug.Conn.send_resp(conn, 403, "private-provider-body") end)
    assert {:error, message} = execute_tool(SaveOVHInvoice, conn, %{"invoice_id" => "INV_US1234567"})
    assert message =~ "HTTP 403"
    assert message =~ "account:apiovh:me/download/get"
    refute message =~ "private-provider-body"

    stranger = insert_user!(%{scopes: ["finance:read", "documents:write"]})
    assert {:error, message} = execute_tool(SaveOVHInvoice, mcp_conn(stranger), %{"invoice_id" => "INV_US1234567"})
    assert message =~ "Connect your own"
  end

  test "does not use a shared OAuth grant or bypass an upstream user restriction", %{conn: conn} do
    reject(Req, :request, 1)

    for fields <- [%{shared_oauth: true}, %{allowed_user_emails: ["someone-else@example.com"]}] do
      server = struct!(UpstreamServer, Map.merge(%{name: "ovh-orders", url: "https://mcp.ovh.example"}, fields))
      stub(Proxy, :fetch_server, fn "ovh-orders" -> {:ok, server} end)
      assert {:error, message} = execute_tool(SaveOVHInvoice, conn, %{"invoice_id" => "INV_US1234567"})
      assert message =~ "Connect your own"
    end
  end

  test "refuses details for a different invoice before downloading", %{conn: conn} do
    stub_http(fn conn ->
      Req.Test.json(conn, %{
        "billId" => "INV_US7654321",
        "date" => "2026-11-05T09:43:00Z",
        "priceWithTax" => %{"value" => 151.61, "currencyCode" => "USD"}
      })
    end)

    reject(SafeHTTP, :fetch, 1)
    assert {:error, message} = execute_tool(SaveOVHInvoice, conn, %{"invoice_id" => "INV_US1234567"})
    assert message =~ "invalid invoice details"
    refute Repo.exists?(Document)
  end

  test "refuses missing scopes and path injection before contacting OVH", %{conn: conn} do
    reject(Req, :request, 1)

    for scopes <- [["finance:read"], ["documents:write"]] do
      user = insert_user!(%{scopes: scopes})
      assert {:error, message} = execute_tool(SaveOVHInvoice, mcp_conn(user), %{"invoice_id" => "INV_US1234567"})
      assert message =~ "scope"
    end

    assert {:error, _} = execute_tool(SaveOVHInvoice, conn, %{"invoice_id" => "../password"})
  end

  test "personal tools are absent from shared identities, Orbit and Automation", %{user: user} do
    stub(Proxy, :list_hoisted_tools, fn _ -> [] end)

    for {tool, name, args} <- [
          {ListOVHInvoices, "ovh_list_invoices", %{}},
          {SaveOVHInvoice, "ovh_save_invoice", %{"invoice_id" => "INV_US1234567"}}
        ] do
      assert name in ToolPolicy.never()
      assert Map.has_key?(DomainRegistry.exclusions(), name)

      for context <- [%{audit_interface: "slack"}, %{mcp_claims: %{"slack_agent" => "operator"}}] do
        conn = %{assigns: Map.put(context, :current_user, user)}
        assert {:error, message} = execute_tool(tool, conn, args)
        assert message =~ "shared Slack"
        response = Server.handle_message(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
        refute Enum.any?(response["result"]["tools"], &(&1["name"] == name))

        response =
          Server.handle_message(conn, %{
            "jsonrpc" => "2.0",
            "id" => 2,
            "method" => "tools/call",
            "params" => %{"name" => name, "arguments" => args}
          })

        assert response["error"]["message"] =~ "not available"
      end
    end
  end

  defp invoice_api do
    stub_http(fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer own-token"]
      assert conn.host == "api.us.ovhcloud.com"

      case conn.request_path do
        "/1.0/me/bill/INV_US1234567" ->
          Req.Test.json(conn, %{
            "billId" => "INV_US1234567",
            "date" => "2026-11-05T09:43:00Z",
            "priceWithTax" => %{"value" => 151.61, "currencyCode" => "USD"},
            "priceWithoutTax" => %{"value" => 127.40, "currencyCode" => "USD"},
            "password" => "private-password",
            "pdfUrl" => "https://login.example/legacy"
          })

        "/1.0/me/bill/INV_US1234567/download" ->
          assert URI.decode_query(conn.query_string) == %{"extension" => "pdf"}
          Req.Test.json(conn, "https://download.ovh.example/invoice?signed=secret")
      end
    end)
  end

  defp connect!(user, token) do
    %OAuthSession{user_id: user.id, server_name: "ovh-orders"}
    |> OAuthSession.changeset(%{
      access_token: token,
      expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
    })
    |> Repo.insert!()
  end

  defp stub_http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
