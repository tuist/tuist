defmodule Atlas.Licenses.Workers.NotifyExpiringLicensesTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Licenses.ExpirationNotifier
  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License
  alias Atlas.Licenses.Workers.NotifyExpiringLicenses
  alias Atlas.Repo

  setup :verify_on_exit!

  test "notifies each license that expires seven days from today" do
    today = Date.utc_today()
    expiring = insert_license!(insert_account!("Expiring Soon"), Date.add(today, 7))
    _too_soon = insert_license!(insert_account!("Too Soon"), Date.add(today, 3))
    _too_far = insert_license!(insert_account!("Too Far"), Date.add(today, 14))
    parent = self()

    expect(ExpirationNotifier, :notify, fn license, opts ->
      send(parent, {:notified, license.id, opts})
      {:ok, %{channel_id: "C1", ts: "1.0"}}
    end)

    assert :ok = NotifyExpiringLicenses.perform(%Oban.Job{})
    assert_received {:notified, notified_id, opts}
    assert notified_id == expiring.id
    assert opts[:today] == today
  end

  test "does nothing when no license expires exactly seven days from today" do
    today = Date.utc_today()
    _too_soon = insert_license!(insert_account!("Too Soon"), Date.add(today, 6))
    _too_far = insert_license!(insert_account!("Too Far"), Date.add(today, 8))

    reject(&ExpirationNotifier.notify/2)

    assert :ok = NotifyExpiringLicenses.perform(%Oban.Job{})
  end

  defp insert_account!(name) do
    %Account{}
    |> Account.changeset(%{
      account_key: "account:license-expiry:#{System.unique_integer([:positive])}",
      name: name,
      segment: :customer
    })
    |> Repo.insert!()
  end

  defp insert_license!(account, expires_on) do
    key = "ONLINE-KEY-#{System.unique_integer([:positive])}"

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
