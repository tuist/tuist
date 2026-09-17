defmodule AtlasWeb.AccountLive.InvoicesViewTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts
  alias AtlasWeb.AccountLive.InvoicesView

  describe "build/2" do
    test "paginates upcoming local invoices" do
      account = insert_account!(%{})

      for index <- 1..6 do
        insert_invoice!(account, %{
          external_id: "invoice:local:#{index}",
          source: "enterprise",
          due_date: Date.add(Date.utc_today(), index),
          number: "LOCAL-#{index}"
        })
      end

      account = Accounts.get_account(account.id)

      assert %{source: :local, page: 2, total_pages: 2, invoices: [invoice]} = InvoicesView.build(account, 2)
      assert invoice.number == "LOCAL-6"
    end

    test "clamps page numbers above the total page count" do
      account = insert_account!(%{})
      insert_invoice!(account, %{external_id: "invoice:one", source: "enterprise", number: "LOCAL-1"})

      account = Accounts.get_account(account.id)

      assert %{page: 1, total_pages: 1} = InvoicesView.build(account, 99)
    end
  end

  test "paginate/3 returns the requested slice" do
    assert InvoicesView.paginate([1, 2, 3, 4, 5], 2, 2) == [3, 4]
  end
end
