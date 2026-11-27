defmodule Atlas.MCP.Tools.MarkStripeInvoicePaidTest do
  use Atlas.MCP.ToolCase, async: true
  use Mimic

  import Ecto.Query

  alias Atlas.Accounts.Invoice
  alias Atlas.Audit.Activity
  alias Atlas.MCP
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.MarkStripeInvoicePaid
  alias Atlas.Repo
  alias Atlas.Stripe
  alias Atlas.TestSupport.StripeClient

  setup do
    suffix = System.unique_integer([:positive])

    account =
      insert_account!(%{
        account_key: "customer:mark-paid-#{suffix}",
        name: "Wire Customer",
        stripe_customer_id: "cus_wire_#{suffix}"
      })

    stored = insert_invoice!(account, %{external_id: "in_wire_#{suffix}", status: "open"})
    %{account: account, stored: stored}
  end

  defp stripe_invoice(account, stored, status) do
    %Stripe.Invoice{
      id: stored.external_id,
      number: stored.number,
      status: status,
      amount_value: Decimal.new("18000.00"),
      amount_currency: "USD",
      customer_id: account.stripe_customer_id,
      dashboard_url: "https://dashboard.stripe.com/invoices/#{stored.external_id}"
    }
  end

  test "a finance:write caller pays only after approving that exact invoice and amount", %{
    account: account,
    stored: stored
  } do
    user = insert_user!(%{scopes: ["finance:write"]})
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    args = %{"account_id" => account.id, "stripe_invoice_id" => stored.external_id}
    test_pid = self()

    StripeClient.put_get_invoice({:ok, stripe_invoice(account, stored, "open")})

    StripeClient.put_pay_invoice_out_of_band(fn {invoice_id, _opts} ->
      send(test_pid, {:paid, invoice_id})
      {:ok, stripe_invoice(account, stored, "paid")}
    end)

    assert {:error, message} = execute_tool(MarkStripeInvoicePaid, conn, args)
    refute_received {:paid, _}
    assert Repo.get!(Invoice, stored.id).status == "open"

    assert [%{id: id, server_name: "stripe", tool_name: "mark-invoice-paid-out-of-band", arguments: approved}] =
             MCP.list_pending_tool_approvals(user)

    assert message =~ "/approvals/#{id}"
    assert approved["amount_value"] == "18000.00"
    assert approved["amount_currency"] == "USD"

    assert {:ok, _} = MCP.decide_tool_approval(user, id, "approved")
    assert {:ok, %{invoice: %{status: "paid"}}} = execute_tool(MarkStripeInvoicePaid, conn, args)
    assert_received {:paid, invoice_id} when invoice_id == stored.external_id

    assert %{metadata: %{"amount_value" => "18000.00", "amount_currency" => "USD", "approval_id" => ^id}} =
             Repo.one!(
               from(a in Activity,
                 where:
                   a.action == "account_invoice.stripe_paid_out_of_band" and
                     a.metadata["stripe_invoice_id"] == ^stored.external_id
               )
             )
  end

  test "an approval does not cover an invoice whose amount changed", %{account: account, stored: stored} do
    user = insert_user!(%{scopes: ["finance:write"]})
    conn = %{assigns: %{current_user: user, audit_interface: "mcp"}}
    args = %{"account_id" => account.id, "stripe_invoice_id" => stored.external_id}

    StripeClient.put_pay_invoice_out_of_band(fn _args -> flunk("must not pay") end)
    StripeClient.put_get_invoice({:ok, stripe_invoice(account, stored, "open")})

    assert {:error, _} = execute_tool(MarkStripeInvoicePaid, conn, args)
    assert [%{id: id}] = MCP.list_pending_tool_approvals(user)
    assert {:ok, _} = MCP.decide_tool_approval(user, id, "approved")

    StripeClient.put_get_invoice(
      {:ok, %{stripe_invoice(account, stored, "open") | amount_value: Decimal.new("180000.00")}}
    )

    assert {:error, message} = execute_tool(MarkStripeInvoicePaid, conn, args)
    assert message =~ "/approvals/"
    assert Repo.get!(Invoice, stored.id).status == "open"
  end

  test "worker, API and Slack contexts cannot mark an invoice paid", %{account: account, stored: stored} do
    user = insert_user!(%{scopes: ["finance:write"]})
    args = %{"account_id" => account.id, "stripe_invoice_id" => stored.external_id}

    StripeClient.put_pay_invoice_out_of_band(fn _args -> flunk("must not pay") end)
    StripeClient.put_get_invoice({:ok, stripe_invoice(account, stored, "open")})

    for assigns <- [
          %{audit_interface: "worker"},
          %{audit_interface: "api"},
          %{audit_interface: "slack"},
          %{audit_interface: "mcp", mcp_claims: %{"slack_agent" => "systems_investigator"}}
        ] do
      conn = %{assigns: Map.put(assigns, :current_user, user)}
      assert {:error, message} = execute_tool(MarkStripeInvoicePaid, conn, args)
      assert message =~ "only callable over Atlas MCP"
    end

    assert MCP.list_pending_tool_approvals(user) == []
  end

  test "the Slack agent's MCP session cannot discover or call the tool, even as a finance:write operator" do
    stub(Proxy, :list_hoisted_tools, fn _conn -> [] end)
    user = insert_user!(%{scopes: ["finance:write"]})

    conn = %{
      assigns: %{
        current_user: user,
        audit_interface: "mcp",
        mcp_claims: %{
          "scopes" => ["mcp"],
          "slack_agent" => "systems_investigator",
          "mcp_tool_groups" => ["contracts", "admin", "hardware", "observability"]
        }
      }
    }

    response = Server.handle_message(conn, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})
    refute "mark_stripe_invoice_paid" in Enum.map(response["result"]["tools"], & &1["name"])

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => "mark_stripe_invoice_paid", "arguments" => %{}}
      })

    assert response["error"]["message"] =~ "not available"
  end

  test "refuses another customer's invoice and invoices that are not open", %{account: account, stored: stored} do
    StripeClient.put_pay_invoice_out_of_band(fn _args -> flunk("must not pay") end)

    StripeClient.put_get_invoice({:ok, %{stripe_invoice(account, stored, "open") | customer_id: "cus_someone_else"}})

    assert {:error, message} =
             execute_tool(MarkStripeInvoicePaid, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => stored.external_id
             })

    assert message =~ "does not belong"

    StripeClient.put_get_invoice({:ok, stripe_invoice(account, stored, "void")})

    assert {:error, message} =
             execute_tool(MarkStripeInvoicePaid, executive_mcp_conn(), %{
               "account_id" => account.id,
               "stripe_invoice_id" => stored.external_id
             })

    assert message =~ "is void"
    assert Repo.get!(Invoice, stored.id).status == "open"
  end
end
