defmodule Atlas.LicensesTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.Licenses
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Users.User

  test "creates an encrypted online license for an Atlas customer and audits it" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    user = insert_user!()
    expires_on = Date.utc_today() |> Date.add(365)

    assert {:ok, %License{} = license} =
             Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
               Licenses.create_license(%{
                 "account_id" => customer.id,
                 "expires_on" => Date.to_iso8601(expires_on)
               })
             end)

    assert license.account.id == customer.id
    assert license.key =~ ~r/^tuist_/
    assert byte_size(Base.decode64!(license.signing_key)) == 32
    assert license.expires_on == expires_on
    assert Enum.map(Licenses.list_licenses(), & &1.id) == [license.id]

    assert %Postgrex.Result{rows: [[stored_key, stored_signing_key, stored_key_hash]]} =
             Ecto.Adapters.SQL.query!(
               Repo,
               "SELECT key, signing_key, key_hash FROM licenses WHERE id = $1::uuid",
               [Ecto.UUID.dump!(license.id)]
             )

    refute stored_key == license.key
    refute stored_key =~ license.key
    refute stored_signing_key == license.signing_key
    assert stored_key_hash == Issuer.key_hash(license.key)

    activity = Repo.get_by!(Activity, action: "license.created", target_id: license.id)
    assert activity.actor_id == user.id
    assert activity.interface == "dashboard"
    assert activity.target_label == "Acme Labs"
    assert activity.metadata["path"] == "/sales/licenses"
    assert activity.metadata["account_path"] == "/sales/accounts/#{customer.id}"
    refute inspect(activity.metadata) =~ license.key
  end

  test "creates a license for an account running a POC" do
    prospect = insert_account!(%{name: "Evaluating Prospect", segment: :prospect, deal_stage: "poc"})
    expires_on = Date.utc_today() |> Date.add(90)

    assert {:ok, %License{} = license} =
             Licenses.create_license(%{
               "account_id" => prospect.id,
               "expires_on" => Date.to_iso8601(expires_on)
             })

    assert license.account.id == prospect.id
    assert license.expires_on == expires_on
  end

  test "rejects accounts that are neither customers nor running a POC" do
    prospect = insert_account!(%{segment: :prospect, deal_stage: "discovery"})

    assert {:error, changeset} =
             Licenses.create_license(%{
               "account_id" => prospect.id,
               "expires_on" => Date.utc_today() |> Date.add(365) |> Date.to_iso8601()
             })

    assert "must belong to a customer or POC account" in errors_on(changeset).account_id
  end

  test "filters, searches, and sorts licenses through connected accounts" do
    alpha = insert_account!(%{name: "Alpha Customer", primary_domain: "alpha.example"})
    zulu = insert_account!(%{name: "Zulu Customer", primary_domain: "zulu.example"})
    alpha_license = insert_license!(alpha)
    zulu_license = insert_license!(zulu)

    customer_filter = %{field: :account_id, operator: :==, value: zulu.id}
    assert Enum.map(Licenses.list_licenses(filters: [customer_filter]), & &1.id) == [zulu_license.id]

    assert Enum.map(Licenses.list_licenses(query: "alpha.example"), & &1.id) == [alpha_license.id]

    assert Enum.map(
             Licenses.list_licenses(sort_by: "customer", sort_order: "asc"),
             & &1.account.name
           ) == ["Alpha Customer", "Zulu Customer"]
  end

  test "paginates beyond the first one hundred licenses with accurate metadata" do
    customer = insert_account!(%{name: "Large Customer", segment: :customer})
    licenses = for _index <- 1..101, do: insert_license!(customer)

    assert {[license], meta} = Licenses.list_licenses_page(page: 2, page_size: 100)
    assert license.id in Enum.map(licenses, & &1.id)
    assert meta.current_page == 2
    assert meta.page_size == 100
    assert meta.total_count == 101
    assert meta.total_pages == 2
  end

  test "returns nil for a malformed license identifier" do
    assert Licenses.get_license("not-a-uuid") == nil
  end

  test "validates an online key without exposing it in the audit trail" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    license = insert_license!(customer)

    {:ok, payload} =
      Audit.with_context(%{interface: "api"}, fn ->
        Licenses.validate_online_key(license.key)
      end)

    assert payload.meta.valid
    assert payload.data.id == license.id
    assert payload.data.attributes.metadata.signingKey == license.signing_key

    activity = Repo.get_by!(Activity, action: "license.validated", target_id: license.id)
    assert activity.interface == "api"
    refute inspect(activity.metadata) =~ license.key

    assert Licenses.validate_online_key("unknown") == {:ok, %{data: nil, meta: %{valid: false}}}
  end

  test "extends a license to a later expiration date and audits both dates" do
    customer = insert_account!(%{name: "Acme Labs", segment: :customer})
    user = insert_user!()
    license = insert_license!(customer)
    previous_expiration_date = license.expires_on
    new_expiration_date = Date.add(previous_expiration_date, 365)

    assert {:ok, extended} =
             Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
               Licenses.extend_license(license, %{"expires_on" => Date.to_iso8601(new_expiration_date)})
             end)

    assert extended.expires_on == new_expiration_date

    activity = Repo.get_by!(Activity, action: "license.extended", target_id: license.id)
    assert activity.actor_id == user.id
    assert activity.metadata["previous_expires_on"] == Date.to_iso8601(previous_expiration_date)
    assert activity.metadata["expires_on"] == Date.to_iso8601(new_expiration_date)
  end

  test "rejects an extension that does not move the expiration date later" do
    license = insert_account!(%{segment: :customer}) |> insert_license!()

    assert {:error, changeset} =
             Licenses.extend_license(license, %{"expires_on" => Date.to_iso8601(license.expires_on)})

    assert "must be after the current expiration date" in errors_on(changeset).expires_on
  end

  test "does not let a stale extension shorten the stored expiration date" do
    license = insert_account!(%{segment: :customer}) |> insert_license!()
    stale_license = Licenses.get_license(license.id)
    later_expiration_date = Date.add(license.expires_on, 730)
    stale_expiration_date = Date.add(license.expires_on, 365)

    assert {:ok, _extended} =
             Licenses.extend_license(license, %{
               "expires_on" => Date.to_iso8601(later_expiration_date)
             })

    assert {:error, changeset} =
             Licenses.extend_license(stale_license, %{
               "expires_on" => Date.to_iso8601(stale_expiration_date)
             })

    assert "must be after the current expiration date" in errors_on(changeset).expires_on
    assert Repo.get!(License, license.id).expires_on == later_expiration_date
  end

  test "checks out and Base64-wraps a locally signed air-gapped certificate" do
    customer = insert_account!(%{name: "Acme & Sons", segment: :customer})
    user = insert_user!()
    license = insert_license!(customer)

    assert {:ok, checkout} =
             Audit.with_context(%{actor: user, interface: "dashboard"}, fn ->
               Licenses.check_out_air_gapped(license)
             end)

    certificate = Base.decode64!(checkout.contents)
    assert certificate =~ "BEGIN LICENSE FILE"
    assert checkout.filename == "acme-sons-tuist-license.key"

    activity = Repo.get_by!(Activity, action: "license.air_gapped_checked_out")
    assert activity.actor_id == user.id
    assert activity.target_id == license.id
    assert activity.metadata["path"] == "/sales/licenses"
    refute inspect(activity.metadata) =~ "certificate"
  end

  test "validates that expiration is not in the past" do
    changeset = Licenses.change_license_request(%{"expires_on" => "2020-01-01"})
    assert "must be today or later" in errors_on(changeset).expires_on
  end

  test "list_licenses_expiring_on/1 returns only licenses whose expires_on matches, with accounts preloaded" do
    target_date = Date.utc_today() |> Date.add(7)
    account = insert_account!(%{name: "Renewal Target"})
    matching = insert_license!(account, expires_on: target_date)
    _earlier = insert_license!(account, expires_on: Date.add(target_date, -1))
    _later = insert_license!(account, expires_on: Date.add(target_date, 1))

    assert [returned] = Licenses.list_licenses_expiring_on(target_date)
    assert returned.id == matching.id
    assert returned.account.id == account.id
    assert returned.account.name == "Renewal Target"
  end

  defp insert_account!(attrs) do
    defaults = %{
      account_key: "account:#{System.unique_integer([:positive])}",
      name: "Account",
      segment: :customer
    }

    %Account{}
    |> Account.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "license-user-#{System.unique_integer([:positive])}@tuist.dev",
      name: "License User",
      role: :executive
    })
    |> Repo.insert!()
  end

  defp insert_license!(account, opts \\ []) do
    key = "ONLINE-KEY-#{System.unique_integer([:positive])}"
    expires_on = Keyword.get(opts, :expires_on, Date.utc_today() |> Date.add(365))

    %License{account_id: account.id}
    |> License.issued_changeset(%{
      key: key,
      key_hash: Issuer.key_hash(key),
      signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
      expires_on: expires_on
    })
    |> Repo.insert!()
  end
end
