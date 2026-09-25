defmodule Tuist.Accounts.Workers.SSOLoginDomainRecheckWorker do
  @moduledoc """
  Daily re-check of every verified login email domain.

  See `Tuist.Accounts.SSOLoginDomainRecheck` for the grace period and for why
  a failed lookup costs a day rather than the verification.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: {23, :hours}, states: :incomplete]

  alias Tuist.Accounts.SSOLoginDomainRecheck

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    SSOLoginDomainRecheck.sweep()

    :ok
  end
end
