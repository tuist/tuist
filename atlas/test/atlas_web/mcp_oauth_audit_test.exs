defmodule AtlasWeb.MCPOAuthAuditTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.FinanceFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Connections.Connection
  alias Atlas.Finance.Config
  alias Atlas.Finance.Providers.Qonto
  alias Atlas.OAuth.AccessTokens
  alias Atlas.Repo

  @source %{key: "qonto-main", provider: :qonto, name: "Qonto", sign_in: "tuist-gmbh-5271", secret_key: "secret"}
  @iban "DE95300107002978231228"

  test "a transfer request made with an OAuth token records which client made it", %{conn: conn} do
    stub(Config, :fetch_source, fn "qonto-main" -> {:ok, @source} end)

    stub(Req, :post, fn %Req.Request{} = request, options ->
      request |> Req.merge(options) |> Req.merge(plug: {Req.Test, Qonto}, retry: false) |> Req.request()
    end)

    Req.Test.stub(Qonto, fn conn ->
      Req.Test.json(conn, %{
        "request_multi_transfer" => %{
          "id" => "req_123",
          "status" => "pending",
          "total_transfers_amount" => "1713.60",
          "total_transfers_amount_currency" => "EUR",
          "total_transfers_count" => 1,
          "scheduled_date" => nil
        }
      })
    end)

    {_session_conn, user} = log_in_user(conn, %{role: :executive})
    insert_qonto_connection!(user)
    paid_before!(@iban)
    jwt = oauth_access_token_fixture(user)
    client_id = AccessTokens.get_by(value: jwt).client.id

    response =
      conn
      |> put_req_header("authorization", "Bearer #{jwt}")
      |> put_req_header("content-type", "application/json")
      |> post(
        "/mcp",
        JSON.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{
            "name" => "finance_create_transfer_request",
            "arguments" => %{
              "source_key" => "qonto-main",
              "note" => "NTT invoice",
              "transfers" => [
                %{
                  "amount" => "1713.60",
                  "iban" => @iban,
                  "name" => "NTT Germany AG & Co. KG",
                  "reference" => "95135757"
                }
              ]
            }
          }
        })
      )
      |> json_response(200)

    refute response["result"]["isError"]

    tool_call = Repo.get_by!(Activity, action: "mcp.tool_called", target_id: "finance_create_transfer_request")
    created = Repo.get_by!(Activity, action: "finance_transfer_request.created", target_id: "req_123")

    assert tool_call.metadata["oauth_client_id"] == client_id
    assert created.metadata["oauth_client_id"] == client_id
    assert [%{"iban" => @iban}] = created.metadata["transfers"]
  end

  defp paid_before!(iban) do
    source = insert_finance_source!()
    account = insert_finance_account!(source)

    insert_finance_transaction!(account, %{
      direction: "debit",
      status: "completed",
      metadata: %{"transfer" => %{"counterparty_account_number" => iban}}
    })
  end

  defp insert_qonto_connection!(user) do
    %Connection{user_id: user.id, provider: "qonto"}
    |> Connection.changeset(%{
      provider_user_id: "membership-1",
      account_name: user.email,
      access_token: "user-access",
      refresh_token: "user-refresh",
      scopes: ["offline_access", "membership.read", "request_transfers.write"],
      expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
    })
    |> Repo.insert!()
  end
end
