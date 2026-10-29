defmodule Atlas.MCP.Tools.CreateAccountTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Accounts.Account
  alias Atlas.MCP.Tools.CreateAccount
  alias Atlas.Repo

  test "creates a manually managed account with a generated key" do
    {:ok, payload} =
      execute_tool(CreateAccount, nil, %{
        "name" => "Northstar Retail",
        "primary_domain" => "northstar.example",
        "segment" => "customer",
        "hosting" => "self_hosted",
        "deal_stage" => "discovery",
        "currency" => "eur",
        "current_value" => 42_000,
        "next_renewal_date" => "2027-03-15"
      })

    assert payload.account.name == "Northstar Retail"
    assert payload.account.account_key == "manual:northstar-example"
    assert payload.account.segment == :customer
    assert payload.account.hosting == "self_hosted"
    assert payload.account.deal_stage == "discovery"
    assert payload.account.currency == "EUR"
    assert payload.account.current_value == "42000.00"
    assert payload.account.next_renewal_date == "2027-03-15"
    assert payload.account_url =~ "/commercial/sales/accounts/#{payload.account.id}"

    stored = Repo.get!(Account, payload.account.id)
    assert stored.account_key == "manual:northstar-example"
  end

  test "defaults to prospect and suffixes duplicate generated keys" do
    insert_account!(%{account_key: "manual:acme-example", name: "Existing"})

    {:ok, payload} =
      execute_tool(CreateAccount, nil, %{
        "name" => "Acme Labs",
        "primary_domain" => "acme.example"
      })

    assert payload.account.account_key == "manual:acme-example-2"
    assert payload.account.segment == :prospect
  end

  test "returns changeset errors" do
    assert {:error, message} = execute_tool(CreateAccount, nil, %{"name" => " "})

    assert message =~ "Could not create account"
    assert message =~ "name"
  end
end
