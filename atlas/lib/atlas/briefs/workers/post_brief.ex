defmodule Atlas.Briefs.Workers.PostBrief do
  use Oban.Worker, queue: :briefs, max_attempts: 3

  alias Atlas.Briefs
  alias Atlas.Briefs.Notifier

  @impl true
  def perform(%Oban.Job{args: %{"subscription_id" => subscription_id}}) do
    case Briefs.get_subscription(subscription_id) do
      nil ->
        {:discard, :subscription_not_found}

      subscription ->
        compose_and_post(subscription)
    end
  end

  defp compose_and_post(subscription) do
    with {:ok, brief} <- Briefs.compose(subscription) do
      maybe_post(subscription, brief)
    end
  end

  defp maybe_post(%{cadence: "daily"}, %{status: "immaterial"}), do: :ok

  defp maybe_post(_subscription, brief) do
    case Notifier.notify(brief) do
      {:ok, _posted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
