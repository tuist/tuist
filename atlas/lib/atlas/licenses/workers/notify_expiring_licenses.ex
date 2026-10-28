defmodule Atlas.Licenses.Workers.NotifyExpiringLicenses do
  @moduledoc """
  Posts a Slack alert for each customer license expiring one week from today.

  Runs daily from the Oban cron; each license is naturally notified once, on the
  day its `expires_on` sits seven days ahead of the current UTC date.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Licenses
  alias Atlas.Licenses.ExpirationNotifier

  @notice_days 7

  @impl true
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    target_date = Date.add(today, @notice_days)

    target_date
    |> Licenses.list_licenses_expiring_on()
    |> Enum.each(&ExpirationNotifier.notify(&1, today: today))

    :ok
  end
end
