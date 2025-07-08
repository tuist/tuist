defmodule Tuist.Accounts.Workers.UpdateAccountUsageWorker do
  @moduledoc ~S"""
  Given an account, we update its usage of various Tuist features such that we can present this information
  to the user without having to run expensive queries against the database.
  """
  use Oban.Worker

  alias Tuist.Accounts

  @impl Oban.Worker

  def perform(%Oban.Job{args: %{"account_id" => account_id, "updated_at" => updated_at_string}}) do
    {:ok, updated_at, _} = DateTime.from_iso8601(updated_at_string)

    Accounts.update_account_current_month_usage(
      account_id,
      Accounts.account_month_usage(account_id, updated_at),
      updated_at: updated_at
    )

    :ok
  end
end
