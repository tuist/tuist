defmodule Atlas.MCP.Tools.ListLicensesTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.MCP.Tools.ListLicenses
  alias Atlas.Repo

  test "lists customer licenses and online keys for executives" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    license = insert_license!(customer)

    assert {:ok, result} = execute_tool(ListLicenses, executive_mcp_conn(), %{})

    assert result.count == 1
    assert result.licenses_url =~ "/sales/licenses"
    assert [serialized] = result.licenses
    assert serialized.id == license.id
    assert serialized.customer_name == "Acme Labs"
    assert serialized.online_key == license.key
    assert serialized.status == "active"
  end

  test "paginates licenses and reports the complete result count" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    first = insert_license!(customer)
    second = insert_license!(customer)

    assert {:ok, result} =
             execute_tool(ListLicenses, executive_mcp_conn(), %{
               "page" => 2,
               "page_size" => 1
             })

    assert result.count == 1
    assert result.total_count == 2
    assert result.page == 2
    assert result.page_size == 1
    assert [serialized] = result.licenses
    assert serialized.id in [first.id, second.id]
  end

  test "rejects non-executive users" do
    conn = insert_user!(%{role: :employee}) |> mcp_conn()

    assert {:error, "License tools are only available to executives."} =
             ListLicenses.execute(conn, %{})
  end

  test "rejects non-object arguments without crashing" do
    assert {:error, "arguments must be an object."} =
             ListLicenses.execute(executive_mcp_conn(), 1)
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
