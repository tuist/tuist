defmodule Atlas.MCP.Tools.ExtendLicenseTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.MCP.Tools.ExtendLicense
  alias Atlas.Repo

  test "extends an existing customer license" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    license = insert_license!(customer)
    new_expiration_date = Date.add(license.expires_on, 365)

    assert {:ok, result} =
             execute_tool(ExtendLicense, executive_mcp_conn(), %{
               "license_id" => license.id,
               "expires_on" => Date.to_iso8601(new_expiration_date)
             })

    assert result.id == license.id
    assert result.expires_on == Date.to_iso8601(new_expiration_date)
    assert Repo.get!(License, license.id).expires_on == new_expiration_date
  end

  test "requires a later expiration date" do
    customer = insert_account!(%{segment: :customer})
    license = insert_license!(customer)

    assert {:error, message} =
             execute_tool(ExtendLicense, executive_mcp_conn(), %{
               "license_id" => license.id,
               "expires_on" => Date.to_iso8601(license.expires_on)
             })

    assert message =~ "must be after the current expiration date"
  end

  test "reports a malformed license identifier" do
    assert {:error, "License not found."} =
             execute_tool(ExtendLicense, executive_mcp_conn(), %{
               "license_id" => "not-a-uuid",
               "expires_on" => Date.utc_today() |> Date.add(365) |> Date.to_iso8601()
             })
  end

  defp insert_license!(customer) do
    key = "ONLINE-KEY-#{System.unique_integer([:positive])}"

    %License{account_id: customer.id}
    |> License.issued_changeset(%{
      key: key,
      key_hash: Issuer.key_hash(key),
      signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
      expires_on: Date.utc_today() |> Date.add(365)
    })
    |> Repo.insert!()
  end
end
