defmodule Atlas.MCP.Tools.FinanceCreateTransferRequestTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Finance.Config
  alias Atlas.MCP.Tools.FinanceCreateTransferRequest

  @source %{key: "qonto-main", provider: :qonto, name: "Qonto", sign_in: "tuist-gmbh-5271", secret_key: "secret"}

  setup do
    stub(Config, :fetch_source, fn
      "qonto-main" -> {:ok, @source}
      _other -> {:error, :source_not_configured}
    end)

    stub(Config, :configured_sources, fn -> [@source] end)

    test_pid = self()

    stub(Req, :post, fn %Req.Request{} = request, options ->
      plug = fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        [key] = Plug.Conn.get_req_header(conn, "x-qonto-idempotency-key")

        send(
          test_pid,
          {:qonto, conn.request_path, Plug.Conn.get_req_header(conn, "authorization"), key, JSON.decode!(body)}
        )

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          JSON.encode!(%{
            "request_multi_transfer" => %{
              "id" => "req_123",
              "status" => "pending",
              "total_transfers_amount" => "2833.83",
              "total_transfers_amount_currency" => "EUR",
              "total_transfers_count" => 2,
              "scheduled_date" => "2026-11-30"
            }
          })
        )
      end

      request
      |> Req.merge(options)
      |> Req.merge(plug: plug, retry: false)
      |> Req.request()
    end)

    :ok
  end

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

  test "creates one pending Qonto multi-transfer request with a stable idempotency key" do
    assert {:ok, result} = execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), @args)
    assert result.id == "req_123"
    assert result.status == "pending"
    assert result.transfer_count == 2

    assert_received {:qonto, "/v2/requests/multi_transfers", ["tuist-gmbh-5271:secret"], key, body}

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

    assert {:ok, _result} = execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), @args)
    assert_received {:qonto, _path, _auth, ^key, _body}

    changed = put_in(@args, ["transfers", Access.at(0), "amount"], "1120.24")
    assert {:ok, _result} = execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), changed)
    assert_received {:qonto, _path, _auth, other_key, _body}
    refute other_key == key
  end

  test "rejects a mistyped IBAN and a malformed amount before calling Qonto" do
    typo = put_in(@args, ["transfers", Access.at(1), "iban"], "DE95300107002978231229")

    assert {:error, message} = execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), typo)
    assert message =~ "transfers[1]"
    assert message =~ "DE95300107002978231229"

    for amount <- ["1,120.23", "1120.234", "0", "-5"] do
      bad = put_in(@args, ["transfers", Access.at(0), "amount"], amount)
      assert {:error, message} = execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), bad)
      assert message =~ "transfers[0]: amount"
    end

    refute_received {:qonto, _path, _auth, _key, _body}
  end

  test "names the configured Qonto sources when the key is unknown" do
    assert {:error, message} =
             execute_tool(FinanceCreateTransferRequest, executive_mcp_conn(), %{@args | "source_key" => "qonto"})

    assert message =~ "qonto-main"
    refute_received {:qonto, _path, _auth, _key, _body}
  end
end
