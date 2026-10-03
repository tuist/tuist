defmodule Atlas.MCP.Tools.CreateLicenseTest do
  use Atlas.MCP.ToolCase

  alias Atlas.MCP.Tools.CreateLicense

  test "creates a license for an Atlas customer" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    expires_on = Date.utc_today() |> Date.add(180)

    assert {:ok, result} =
             execute_tool(CreateLicense, executive_mcp_conn(), %{
               "account_id" => customer.id,
               "expires_on" => Date.to_iso8601(expires_on)
             })

    assert result.account_id == customer.id
    assert result.customer_name == "Acme Labs"
    assert result.online_key =~ ~r/^tuist_/
    assert result.expires_on == Date.to_iso8601(expires_on)
  end

  test "creates a license for an account running a POC" do
    prospect = insert_account!(%{name: "Audi", segment: :prospect, deal_stage: "poc"})
    expires_on = Date.utc_today() |> Date.add(90)

    assert {:ok, result} =
             execute_tool(CreateLicense, executive_mcp_conn(), %{
               "account_id" => prospect.id,
               "expires_on" => Date.to_iso8601(expires_on)
             })

    assert result.account_id == prospect.id
    assert result.customer_name == "Audi"
    assert result.online_key =~ ~r/^tuist_/
  end

  test "rejects accounts that are neither customers nor running a POC" do
    lead = insert_account!(%{name: "Cold Lead"})

    assert {:error, message} =
             execute_tool(CreateLicense, executive_mcp_conn(), %{
               "account_id" => lead.id,
               "expires_on" => Date.utc_today() |> Date.add(365) |> Date.to_iso8601()
             })

    assert message =~ "must belong to a customer or POC account"
  end

  test "requires an account and expiration date" do
    assert {:error, "account_id and expires_on are required."} =
             CreateLicense.execute(executive_mcp_conn(), %{})
  end

  test "reports a malformed account identifier" do
    assert {:error, message} =
             execute_tool(CreateLicense, executive_mcp_conn(), %{
               "account_id" => "not-a-uuid",
               "expires_on" => Date.utc_today() |> Date.add(365) |> Date.to_iso8601()
             })

    assert message =~ "account_id: is invalid"
  end
end
