defmodule Atlas.Push.Workers.Deliver do
  @moduledoc """
  Delivers one notification to one registration.

  Arguments hold IDs, the fixed kind and destination, and an expiry; never a
  provider token. Each attempt revalidates the kind and destination, reloads the
  registration and requires it to be live and still owned by the intended user,
  so sign-out, account switches and token invalidation cancel queued deliveries.
  Expired notifications are cancelled rather than delivered late. Retries back
  off exponentially and honor provider `Retry-After` within the notification's
  lifetime. Terminal outcomes are audited without tokens.

  Uniqueness on `[registration_id, notification_id]` guards individual inserts.
  `Atlas.Push.notify_user/4` uses `Oban.insert_all/1`, which the Basic engine
  inserts without unique checks; it relies on a fresh notification ID and
  distinct registration IDs instead.
  """
  use Oban.Worker,
    queue: :push,
    max_attempts: 5,
    unique: [keys: [:registration_id, :notification_id], period: 86_400]

  alias Atlas.Push
  alias Atlas.Push.APNs
  alias Atlas.Push.FCM
  alias Atlas.Push.Installation
  alias Atlas.Push.Message

  @max_retry_after_seconds 3600

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    with {:ok, expires_at} <- expires_at(args),
         true <- Push.valid_notification?(args["kind"], {args["screen"], args["record_id"]}),
         {:ok, notification_id} <- Ecto.UUID.cast(args["notification_id"]),
         :ok <- ensure_unexpired(expires_at),
         %Installation{} = installation <- Push.deliverable(args["registration_id"], args["user_id"]) do
      opts = [expires_at: expires_at, collapse_id: notification_id]

      message = %{
        registration_id: installation.id,
        notification_id: notification_id,
        screen: args["screen"],
        record_id: args["record_id"]
      }

      installation
      |> send_message(message, opts)
      |> handle_result(installation, args, expires_at, attempt >= max_attempts)
    else
      :expired -> {:cancel, :expired}
      nil -> {:cancel, :registration_unavailable}
      _ -> {:cancel, :invalid_arguments}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: min(trunc(:math.pow(2, attempt) * 5), 600)

  defp send_message(%Installation{platform: "ios"} = installation, message, opts),
    do: APNs.deliver(installation, Message.apns_payload(message), opts)

  defp send_message(%Installation{platform: "android"} = installation, message, opts),
    do: FCM.deliver(installation, Message.fcm_data(message), opts)

  defp handle_result(:ok, installation, args, _expires_at, _last?) do
    Push.audit_delivery(installation, args, "delivered")
    :ok
  end

  defp handle_result({:invalid_token, opts}, installation, args, _expires_at, _last?) do
    reason =
      case Push.retire_invalidated(installation, opts) do
        :retired -> :token_invalidated
        :kept -> :token_rejected_after_refresh
      end

    Push.audit_delivery(installation, args, "cancelled", reason)
    {:cancel, reason}
  end

  defp handle_result({:retry, nil}, installation, args, _expires_at, last?) do
    if last?, do: Push.audit_delivery(installation, args, "failed", :provider_unavailable)
    {:error, :provider_unavailable}
  end

  defp handle_result({:retry, seconds}, installation, args, expires_at, _last?) do
    if DateTime.before?(DateTime.add(DateTime.utc_now(), seconds), expires_at) do
      {:snooze, min(max(seconds, 1), @max_retry_after_seconds)}
    else
      Push.audit_delivery(installation, args, "cancelled", :expired)
      {:cancel, :expired}
    end
  end

  defp handle_result({:error, reason}, installation, args, _expires_at, _last?) do
    Push.audit_delivery(installation, args, "cancelled", reason)
    {:cancel, reason}
  end

  defp expires_at(%{"expires_at" => value}) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, expires_at, _offset} -> {:ok, expires_at}
      _ -> :error
    end
  end

  defp expires_at(_args), do: :error

  defp ensure_unexpired(expires_at) do
    if DateTime.before?(DateTime.utc_now(), expires_at), do: :ok, else: :expired
  end
end
