defmodule Tuist.Kura.Workers.ProvisionOnDemandWorker do
  @moduledoc """
  Brings up an account's Kura instance as soon as a client asks for a cache
  endpoint the account has no instance serving.

  Cache-endpoint resolution enqueues this when it answers with no Kura
  endpoint. Without it a returning account waited for its demand to leave the
  node's buffer (flushed every minute) and then for the reconciler tick (also
  every minute) before its instance even started coming back. This runs the
  same provisioning rules for that one account at once
  (`Tuist.Kura.Lifecycle.provision_account/2`), applies each instance that is
  coming up (`Tuist.Kura.Reconciler.reconcile_server/1`), and hands each to
  `Tuist.Kura.Workers.AwaitActivationWorker`. The tick stays the authority and
  converges anything this misses.

  One job per account waits in the queue at a time, so every client of an
  account asking at once costs one provisioning pass.
  """
  use Oban.Worker,
    queue: :kura_provisioning,
    max_attempts: 1,
    unique: [keys: [:account_id], period: :infinity, states: :incomplete]

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.Lifecycle
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Workers.AwaitActivationWorker

  def enqueue(%Account{id: account_id}) do
    %{account_id: account_id, requested_at: DateTime.to_iso8601(DateTime.utc_now())}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "requested_at" => requested_at}}) do
    if Environment.kura_control_plane?() do
      {:ok, requested_at, _offset} = DateTime.from_iso8601(requested_at)
      {:ok, servers} = Lifecycle.provision_account(account_id, requested_at)

      Enum.each(servers, fn server ->
        :ok = Reconciler.reconcile_server(server)
        {:ok, _job} = AwaitActivationWorker.enqueue(server)
      end)
    end

    :ok
  end
end
