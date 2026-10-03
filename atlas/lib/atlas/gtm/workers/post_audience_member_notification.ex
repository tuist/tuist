defmodule Atlas.GTM.Workers.PostAudienceMemberNotification do
  @moduledoc """
  Posts one newly added audience member to the company Slack #gtm channel.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args]]

  alias Atlas.Audit
  alias Atlas.GTM.AudienceMemberNotifier
  alias Atlas.GTM.AudienceMembership
  alias Atlas.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"membership_id" => membership_id, "notification_id" => notification_id}})
      when is_binary(membership_id) and is_binary(notification_id) do
    Audit.with_context(%{interface: "worker"}, fn ->
      case Repo.get(AudienceMembership, membership_id) do
        nil ->
          {:cancel, :membership_not_found}

        %AudienceMembership{status: status} when status != "subscribed" ->
          {:cancel, :membership_not_subscribed}

        %AudienceMembership{} = membership ->
          membership
          |> Repo.preload([:audience, :subscriber])
          |> announce(notification_id)
      end
    end)
  end

  defp announce(%AudienceMembership{} = membership, notification_id) do
    case AudienceMemberNotifier.announce(membership.audience, membership.subscriber, notification_id) do
      {:ok, response} ->
        Audit.record("gtm_audience.subscriber_announced", %{
          target_type: "gtm_audience",
          target_id: membership.audience.id,
          target_label: membership.audience.name,
          metadata: %{
            dashboard_path: AudienceMemberNotifier.dashboard_path(membership.audience),
            subscriber_id: membership.subscriber.id,
            subscriber_email: membership.subscriber.email,
            slack_channel_id: AudienceMemberNotifier.channel_id(),
            slack_message_ts: response["ts"]
          }
        })

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
