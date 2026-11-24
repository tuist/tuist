defmodule Atlas.MCP.Tools.FinanceCreateTransferRequestTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Connection
  alias Atlas.Finance.Config
  alias Atlas.MCP.Tools.FinanceCreateTransferRequest

  @source %{key: "qonto-main", provider: :qonto, name: "Qonto", sign_in: "tuist-gmbh-5271", secret_key: "secret"}

  @args %{
    "source_key" => "qonto-main",
    "note" => "Rack invoices",
    "scheduled_date" => "2026-11-30",
    "transfers" => [
      %{
        "amount" => "1120.23",
        "iban" => "FR76 1778 9000 0110 5506 2300 111",
        "name" => "COGENT IPV4 LLC",
        "reference" => "SINVDE159058"
      },
      %{
        "amount" => "1713.60",
        "iban" => "de95 3001 0700 2978 2312 28",
        "name" => "NTT Germany AG & Co. KG",
        "reference" => "95135757"
      }
    ]
  }

  setup do
    stub(Config, :fetch_source, fn
      "qonto-main" -> {:ok, @source}
      _other -> {:error, :source_not_configured}
    end)

    stub(Config, :configured_sources, fn -> [@source] end)

    stub(Atlas.Connections.Config, :credentials, fn _ -> %{client_id: "qonto-client", client_secret: "qonto-secret"} end)

    test_pid = self()

    stub(Req, :post, fn %Req.Request{} = request, options ->
      request
      |> Req.merge(options)
      |> Req.merge(plug: &qonto(&1, test_pid), retry: false)
      |> Req.request()
    end)

    user = insert_user!(%{role: :executive})
    insert_qonto_connection!(user)
    %{conn: mcp_conn(user), user: user}
  end

  test "creates one pending Qonto multi-transfer request with the caller's OAuth grant", %{conn: conn} do
    assert {:ok, result} = execute_tool(FinanceCreateTransferRequest, conn, @args)
    assert result.id == "req_123"
    assert result.status == "pending"
    assert result.transfer_count == 2

    assert_received {:qonto, "/v2/requests/multi_transfers", "Bearer user-access", key, body}

    assert %{
             "request_multi_transfer" => %{
               "note" => "Rack invoices",
               "scheduled_date" => "2026-11-30",
               "transfers" => [cogent, ntt]
             }
           } = body

    refute Map.has_key?(body["request_multi_transfer"], "debit_iban")

    assert cogent == %{
             "amount" => "1120.23",
             "currency" => "EUR",
             "credit_account_currency" => "EUR",
             "credit_iban" => "FR7617789000011055062300111",
             "credit_account_name" => "COGENT IPV4 LLC",
             "reference" => "SINVDE159058"
           }

    assert ntt["credit_iban"] == "DE95300107002978231228"
    assert Repo.get_by!(Activity, action: "finance_transfer_request.created", target_id: "req_123")

    assert {:ok, _result} = execute_tool(FinanceCreateTransferRequest, conn, @args)
    assert_received {:qonto, _path, _auth, ^key, _body}

    changed = put_in(@args, ["transfers", Access.at(0), "amount"], "1120.24")
    assert {:ok, _result} = execute_tool(FinanceCreateTransferRequest, conn, changed)
    assert_received {:qonto, _path, _auth, other_key, _body}
    refute other_key == key
  end

  test "refreshes a rejected token once and retries with the same idempotency key", %{conn: conn, user: user} do
    Repo.update_all(Connection, set: [access_token: "rejected-access"])

    stub(Req, :request, fn
      %Req.Request{} = request ->
        call_original(Req, :request, [request])

      opts ->
        assert opts[:url] == "https://oauth.qonto.com/oauth2/token"
        assert opts[:form]["grant_type"] == "refresh_token"
        assert opts[:form]["refresh_token"] == "user-refresh"
        {:ok, %Req.Response{status: 200, body: %{"access_token" => "fresh-access", "refresh_token" => "next-refresh"}}}
    end)

    assert {:ok, %{id: "req_123"}} = execute_tool(FinanceCreateTransferRequest, conn, @args)
    assert_received {:qonto, _path, "Bearer rejected-access", key, _body}
    assert_received {:qonto, _path, "Bearer fresh-access", ^key, _body}
    assert Repo.get_by!(Connection, user_id: user.id).refresh_token == "next-refresh"
  end

  test "points a caller without a Qonto connection to Connections" do
    assert {:error, message} = execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), @args)
    assert message =~ "/settings/connections"
    refute_received {:qonto, _path, _auth, _key, _body}
  end

  test "rejects a mistyped IBAN and a malformed amount before calling Qonto", %{conn: conn} do
    typo = put_in(@args, ["transfers", Access.at(1), "iban"], "DE95300107002978231229")

    assert {:error, message} = execute_tool(FinanceCreateTransferRequest, conn, typo)
    assert message =~ "transfers[1]"
    assert message =~ "DE95300107002978231229"

    for amount <- ["1,120.23", "1120.234", "0", "-5"] do
      bad = put_in(@args, ["transfers", Access.at(0), "amount"], amount)
      assert {:error, message} = execute_tool(FinanceCreateTransferRequest, conn, bad)
      assert message =~ "transfers[0]: amount"
    end

    refute_received {:qonto, _path, _auth, _key, _body}
  end

  test "names the configured Qonto sources when the key is unknown", %{conn: conn} do
    assert {:error, message} = execute_tool(FinanceCreateTransferRequest, conn, %{@args | "source_key" => "qonto"})

    assert message =~ "qonto-main"
    refute_received {:qonto, _path, _auth, _key, _body}
  end

  defp qonto(conn, test_pid) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    [key] = Plug.Conn.get_req_header(conn, "x-qonto-idempotency-key")
    [auth] = Plug.Conn.get_req_header(conn, "authorization")
    send(test_pid, {:qonto, conn.request_path, auth, key, JSON.decode!(body)})

    {status, response} =
      if auth == "Bearer rejected-access" do
        {401, %{"errors" => [%{"code" => "unauthorized"}]}}
      else
        {200,
         %{
           "request_multi_transfer" => %{
             "id" => "req_123",
             "status" => "pending",
             "total_transfers_amount" => "2833.83",
             "total_transfers_amount_currency" => "EUR",
             "total_transfers_count" => 2,
             "scheduled_date" => "2026-11-30"
           }
         }}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, JSON.encode!(response))
  end

  defp insert_qonto_connection!(user) do
    %Connection{user_id: user.id, provider: "qonto"}
    |> Connection.changeset(%{
      provider_user_id: "membership-1",
      account_name: "marek@tuist.dev",
      access_token: "user-access",
      refresh_token: "user-refresh",
      scopes: ["offline_access", "membership.read", "request_transfers.write"],
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })
    |> Repo.insert!()
  end
end
