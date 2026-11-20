defmodule LuftServer.Notifications.ThreadFinishedWorker do
  @moduledoc """
  Tells a thread's owner on their Luft devices that the thread stopped
  working (it replied, failed or was stopped), one `DeliveryWorker` job per
  device. Enqueued by `LuftServer.Notifications.notify_thread_finished/2` in the transaction
  that sets the status.

  The alert shows a fixed line for the status and, once the agent named the
  thread, its title; never message content. A thread starts titled with the
  start of its first message, so until it's renamed the alert says "Your
  thread". `url` is the thread's Luft web URL on this server, which Luft
  opens; `account` is the handle of the account that owns the thread, which
  Luft selects first; and `user` is the owner's handle, so Luft opens it in
  the owner's profile. Tuist's generic dispatch endpoint chooses the user's
  devices and validates the receiving sign-in again before APNs delivery.

  It also reminds the owner when a thread's timed snooze ends (status
  `snooze_ended`), and stays quiet about a thread that stops while it is
  snoozed until a later time: that reminder covers it.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:thread_id, :revision, :status],
      states: [:available, :scheduled, :retryable, :completed]
    ]

  import Ecto.Query

  alias LuftServer.Notifications.Delegation
  alias LuftServer.Notifications.Transport
  alias LuftServer.Repo
  alias LuftServer.Sessions.Session
  alias LuftServer.Threads.Thread

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id, "status" => status} = args}) do
    with %Thread{} = thread <- Repo.get(Thread, thread_id),
         true <- thread.status == :active,
         false <- status != "snooze_ended" and snoozed?(thread) do
      subject = to_string(thread.owner_id)

      sessions =
        Repo.all(
          from s in Session, where: s.user_sub == ^subject and s.expires_at > ^DateTime.utc_now()
        )

      Enum.reduce_while(sessions, :ok, fn session, :ok ->
        case deliver(thread, session, args["revision"], status) do
          {:ok, _} -> {:cont, :ok}
          {:error, :unauthorized} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      _ -> :ok
    end
  end

  defp deliver(thread, session, revision, status) do
    actor = Delegation.actor(session.id, thread.owner_id)

    if actor && Delegation.readable?(thread, actor) do
      payload = payload(thread, thread.account_handle, session.handle, status)

      Transport.request(session.id, :post, "/api/me/luft-notifications", %{
        "kind" => "alert",
        "notification_id" => "#{thread.id}:#{revision}:#{status}",
        "payload" => Map.put(payload, "url", "/luft/threads/#{thread.id}")
      })
    else
      {:error, :unauthorized}
    end
  end

  defp payload(%Thread{id: id} = thread, account_handle, owner_handle, status) do
    %{
      "account" => account_handle,
      "user" => owner_handle,
      "thread_id" => id,
      "aps" => %{
        "alert" => %{"title" => Delegation.thread_title(thread), "body" => body(status)},
        "sound" => "default",
        "thread-id" => id
      }
    }
  end

  # The timed snooze worker reminds the owner when the snooze ends.
  defp snoozed?(%Thread{snoozed_until: until}),
    do: until != nil and DateTime.after?(until, DateTime.utc_now())

  defp body("snooze_ended"), do: "Your snooze is over. Tap to pick it up."
  defp body("idle"), do: "Replied. Tap to read it."
  defp body("waiting"), do: "Needs your decision. Tap to answer."
  defp body("failed"), do: "Couldn't finish. Tap to see what happened."

  defp body("outcome_unknown"),
    do: "Stopped while a tool was running. Check it before continuing."

  defp body(_status), do: "Was interrupted. Send a message to continue."
end
