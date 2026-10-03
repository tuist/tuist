defmodule Atlas.Briefs.Workers.ScheduleBriefs do
  use Oban.Worker, queue: :briefs, max_attempts: 3

  alias Atlas.Briefs
  alias Atlas.Briefs.Workers.PostBrief

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"cadence" => cadence}}) when cadence in ["daily", "weekly", "monthly"] do
    if cadence == "monthly" and not last_day_of_month?(Date.utc_today()) do
      :ok
    else
      ensure_subscriptions()

      case Briefs.list_subscriptions(cadence: cadence, enabled: true) do
        [] ->
          Logger.warning("No enabled #{cadence} brief subscriptions, so no brief will be posted")
          :ok

        subscriptions ->
          subscriptions
          |> Enum.map(&enqueue_brief/1)
          |> Enum.find_value(:ok, fn
            {:error, reason} -> {:error, reason}
            _result -> false
          end)
      end
    end
  end

  def last_day_of_month?(%Date{} = date), do: date == Date.end_of_month(date)

  defp ensure_subscriptions do
    case Briefs.ensure_default_subscriptions() do
      {:ok, _subscriptions} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not ensure default brief subscriptions: #{inspect(reason)}")
        :ok
    end
  end

  defp enqueue_brief(subscription) do
    %{"subscription_id" => subscription.id}
    |> PostBrief.new(
      unique: [
        period: 3_600,
        fields: [:worker, :args],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
    |> Oban.insert()
  end
end
