defmodule Tuist.Accounts.Workers.UpdateAccountUsageWorker do
  @moduledoc ~S"""
  Given an account, we update its usage of various Tuist features such that we can present this information
  to the user without having to run expensive queries against the database.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Time

  @impl Oban.Worker

  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    updated_at = Time.utc_now()

    Accounts.update_account_current_month_usage(
      account_id,
      Accounts.account_month_usage(account_id, updated_at),
      updated_at: updated_at
    )

    AirUsageNotifications.enqueue(account_id, updated_at)
    :ok
  end
end
