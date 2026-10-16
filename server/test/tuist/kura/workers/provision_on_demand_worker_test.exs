defmodule Tuist.Kura.Workers.ProvisionOnDemandWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.Account
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Server
  alias Tuist.Kura.Workers.AwaitActivationWorker
  alias Tuist.Kura.Workers.ProvisionOnDemandWorker

  setup :set_mimic_from_context

  setup do
    stub(Tuist.Environment, :kura_control_plane?, fn -> true end)
    :ok
  end

  test "brings the account's instance up, applies it at once and polls for its activation" do
    server = %Server{id: UUIDv7.generate(), account_id: 42}
    requested_at = ~U[2026-09-16 12:00:00Z]

    expect(Lifecycle, :provision_account, fn 42, ^requested_at, [traffic: false] -> {:ok, [server]} end)
    expect(Reconciler, :reconcile_server, fn ^server -> :ok end)

    assert :ok =
             perform_job(ProvisionOnDemandWorker, %{
               "account_id" => 42,
               "requested_at" => DateTime.to_iso8601(requested_at)
             })

    assert_enqueued(worker: AwaitActivationWorker, args: %{"server_id" => server.id})
  end

  test "does nothing when this process is not the Kura control plane" do
    stub(Tuist.Environment, :kura_control_plane?, fn -> false end)
    reject(&Lifecycle.provision_account/3)

    assert :ok = perform_job(ProvisionOnDemandWorker, %{"account_id" => 42, "requested_at" => "2026-09-16T12:00:00Z"})
  end

  test "provisions as traffic for a request the activation gateway admitted" do
    account = %Account{id: 42}
    requested_at = ~U[2026-09-16 12:00:00Z]
    expect(Lifecycle, :provision_account, fn 42, ^requested_at, [traffic: true] -> {:ok, []} end)

    {:ok, job} = ProvisionOnDemandWorker.enqueue(account, traffic: true)

    assert :ok =
             perform_job(ProvisionOnDemandWorker, %{job.args | requested_at: DateTime.to_iso8601(requested_at)})
  end

  test "keeps one request per account in the queue" do
    account = %Account{id: 42}

    {:ok, _job} = ProvisionOnDemandWorker.enqueue(account)
    {:ok, _job} = ProvisionOnDemandWorker.enqueue(account)

    assert [_job] = all_enqueued(worker: ProvisionOnDemandWorker)
  end
end
