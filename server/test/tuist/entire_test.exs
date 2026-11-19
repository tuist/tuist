defmodule Tuist.EntireTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Entire
  alias Tuist.Entire.Client
  alias Tuist.Entire.Delivery
  alias Tuist.Entire.Installation
  alias Tuist.Entire.InstallRequest
  alias Tuist.Entire.Workers.DeliveryWorker
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "deduplicates delivery IDs and JWT IDs before queuing durable processing" do
    delivery = %{"delivery_id" => "delivery-one", "installation_id" => "ins_one"}
    assert {:ok, _} = Entire.accept_delivery(delivery, "jwt-one")
    assert {:ok, _} = Entire.accept_delivery(delivery, "jwt-two")
    assert {:ok, _} = Entire.accept_delivery(%{delivery | "delivery_id" => "delivery-two"}, "jwt-one")
    assert Repo.aggregate(Delivery, :count) == 1
    assert [%{args: ^delivery}] = all_enqueued(worker: DeliveryWorker)
  end

  test "applies installation lifecycle revisions monotonically" do
    account = AccountsFixtures.user_fixture().account
    installation = Repo.insert!(%Installation{account_id: account.id, remote_id: "ins_lifecycle"})

    lifecycle = fn action, revision ->
      Entire.handle_delivery(%{
        "installation_id" => installation.remote_id,
        "event" => %{"type" => "installation.#{action}", "payload" => %{"installation" => %{"revision" => revision}}}
      })
    end

    assert :ok = lifecycle.("suspended", 7)
    assert %{active: false, revision: 7} = Repo.reload!(installation)
    assert :ok = lifecycle.("resumed", 6)
    assert %{active: false, revision: 7} = Repo.reload!(installation)
    assert :ok = lifecycle.("repositories_added", 9)
    assert :ok = lifecycle.("resumed", 8)
    assert :ok = lifecycle.("suspended", 7)
    assert %{active: true, revision: 8} = Repo.reload!(installation)
    assert :ok = lifecycle.("repositories_removed", 11)
    assert :ok = lifecycle.("suspended", 10)
    assert %{active: false, revision: 10} = Repo.reload!(installation)
    assert :ok = lifecycle.("resumed", 12)
    assert :ok = lifecycle.("permissions_changed", 14)
    assert :ok = lifecycle.("deleted", 13)
    assert %{active: false, revision: 13} = Repo.reload!(installation)
  end

  test "installation states expire, are account-scoped and cannot transfer an installation" do
    account = AccountsFixtures.user_fixture().account
    other = AccountsFixtures.user_fixture().account
    stub(Client, :verify_receipt, fn _, _ -> {:ok, %{"installation_id" => "ins_shared"}} end)
    assert {:ok, state} = Entire.begin_install(account)
    assert {:error, :invalid_state} = Entire.finish_install(other, state, "receipt")
    assert {:ok, _} = Entire.finish_install(account, state, "receipt")
    assert {:error, :invalid_state} = Entire.finish_install(account, state, "receipt")
    assert {:ok, other_state} = Entire.begin_install(other)
    assert {:error, :installation_already_connected} = Entire.finish_install(other, other_state, "receipt")

    assert {:ok, expired} = Entire.begin_install(account)
    expired_request = Repo.get!(InstallRequest, expired)
    Repo.update!(Ecto.Changeset.change(expired_request, expires_at: DateTime.add(DateTime.utc_now(:second), -1)))
    assert {:error, :invalid_state} = Entire.finish_install(account, expired, "receipt")
  end
end
