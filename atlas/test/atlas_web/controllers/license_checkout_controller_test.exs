defmodule AtlasWeb.LicenseCheckoutControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Audit.Activity
  alias Atlas.Licenses.Config
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Repo

  test "downloads a Base64-wrapped air-gapped license for executives", %{conn: conn} do
    {conn, user} = log_in_user(conn, %{email: "license-download@example.com", role: :executive})
    customer = insert_account!()
    license = insert_license!(customer)

    conn = get(conn, ~p"/commercial/sales/licenses/#{license.id}/air-gapped")

    certificate = conn |> response(200) |> Base.decode64!()
    assert certificate =~ "BEGIN LICENSE FILE"

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="acme-labs-tuist-license.key")]

    activity = Repo.get_by!(Activity, action: "license.air_gapped_checked_out")
    assert activity.actor_id == user.id
    assert activity.interface == "dashboard"
  end

  test "forbids non-executive users", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-download-employee@example.com", role: :employee})
    license = insert_account!() |> insert_license!()

    conn = get(conn, ~p"/commercial/sales/licenses/#{license.id}/air-gapped")

    assert response(conn, 403)
  end

  test "returns not found for an unknown license", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-download-missing@example.com", role: :executive})

    conn = get(conn, ~p"/commercial/sales/licenses/#{Ecto.UUID.generate()}/air-gapped")

    assert response(conn, 404)
  end

  test "returns not found for a malformed license identifier", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{email: "license-download-malformed@example.com", role: :executive})

    conn = get(conn, "/commercial/sales/licenses/not-a-uuid/air-gapped")

    assert response(conn, 404)
  end

  test "returns executives to the dashboard when signing is unavailable", %{conn: conn} do
    stub(Config, :signing_private_key, fn -> nil end)

    {conn, _user} = log_in_user(conn, %{email: "license-download-unavailable@example.com", role: :executive})
    license = insert_account!() |> insert_license!()

    conn = get(conn, ~p"/commercial/sales/licenses/#{license.id}/air-gapped")

    assert redirected_to(conn) == ~p"/commercial/sales/licenses"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Atlas license signing is not configured."
  end

  defp insert_account! do
    %Account{}
    |> Account.changeset(%{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Acme Labs",
      segment: :customer
    })
    |> Repo.insert!()
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
