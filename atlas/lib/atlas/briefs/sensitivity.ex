defmodule Atlas.Briefs.Sensitivity do
  @moduledoc false

  alias Atlas.Briefs.Subscription
  alias Atlas.Evidence
  alias Atlas.Repo
  alias Atlas.Slack.Channel

  @doc """
  Resolves the most sensitive content a subscription's channel may receive.

  A channel Atlas has never synced is an unknown quantity: it may be
  externally shared, so it cannot be treated as a safe destination. That case
  returns an error instead of a `public` ceiling, so callers fail loudly rather
  than composing a brief whose every restricted item is silently filtered out.
  """
  def ceiling(%Subscription{} = subscription) do
    case Repo.get_by(Channel,
           slack_app: slack_app(subscription.slack_app),
           channel_id: subscription.slack_channel_id
         ) do
      %Channel{is_ext_shared: true} -> {:ok, "public"}
      %Channel{} -> {:ok, subscription.max_sensitivity}
      nil -> {:error, :slack_channel_not_synced}
    end
  end

  def permits?(ceiling, sensitivity) when is_binary(ceiling) do
    Evidence.permits?(ceiling, sensitivity)
  end

  def max(values) do
    Enum.reduce(values, "public", &Evidence.most_sensitive/2)
  end

  def validate_subscription(%Subscription{} = subscription) do
    with {:ok, ceiling} <- ceiling(subscription) do
      if permits?(ceiling, subscription.max_sensitivity),
        do: :ok,
        else: {:error, :subscription_exceeds_channel_sensitivity}
    end
  end

  defp slack_app("community"), do: :community
  defp slack_app(_app), do: :company
end
