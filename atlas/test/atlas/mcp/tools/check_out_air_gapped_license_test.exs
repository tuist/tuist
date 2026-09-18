defmodule Atlas.MCP.Tools.CheckOutAirGappedLicenseTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.MCP.Tools.CheckOutAirGappedLicense
  alias Atlas.Repo

  test "checks out an air-gapped license file for executives" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    license = insert_license!(customer)

    assert {:ok, result} =
             execute_tool(CheckOutAirGappedLicense, executive_mcp_conn(), %{
               "license_id" => license.id
             })

    assert result.license_id == license.id
    assert result.filename == "acme-labs-tuist-license.key"
    assert result.license_file_base64 |> Base.decode64!() =~ "BEGIN LICENSE FILE"
    assert result.expires_on == Date.to_iso8601(license.expires_on)
  end

  test "reports unknown licenses" do
    assert {:error, "License not found."} =
             CheckOutAirGappedLicense.execute(executive_mcp_conn(), %{
               "license_id" => Ecto.UUID.generate()
             })
  end

  test "reports malformed license identifiers" do
    assert {:error, "License not found."} =
             execute_tool(CheckOutAirGappedLicense, executive_mcp_conn(), %{
               "license_id" => "not-a-uuid"
             })
  end

  test "preserves the executive-only authorization error" do
    conn = insert_user!(%{role: :employee}) |> mcp_conn()

    assert {:error, "License tools are only available to executives."} =
             CheckOutAirGappedLicense.execute(conn, %{"license_id" => Ecto.UUID.generate()})
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
