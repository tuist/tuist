defmodule Tuist.Push.Workers.ThreadFinishedWorker do
  @moduledoc """
  Tells a thread's owner on their Luft devices that the thread stopped
  working (it replied, failed or was stopped), one `DeliveryWorker` job per
  device. Enqueued by `Tuist.Push.notify_thread_finished/2` in the transaction
  that sets the status.

  The alert shows a fixed line for the status and, once the agent named the
  thread, its title; never message content. A thread starts titled with the
  start of its first message, so until it's renamed the alert says "Your
  thread". `url` is the thread's Luft web URL on this server, which Luft
  opens; `account` is the handle of the account that owns the thread, which
  Luft selects first; and `user` is the owner's handle, so Luft opens it in
  the owner's profile. Luft registers only Apple devices (see
  `Tuist.Push.register/4`), so it sends nothing when APNs isn't configured.

  It also reminds the owner when a thread's timed snooze ends (status
  `snooze_ended`), and stays quiet about a thread that stops while it is
  snoozed until a later time: that reminder covers it.
  """

  use Oban.Worker, queue: :push, max_attempts: 3

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Push
  alias Tuist.Push.APNs
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Repo
  alias Tuist.Threads.Thread

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id, "status" => status}}) do
    with %Thread{} = thread <- Repo.get(Thread, thread_id),
         false <- status != "snooze_ended" and snoozed?(thread),
         {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
         %{account: %{name: owner_handle}} <- Accounts.get_user_by_id(thread.owner_id) do
      if APNs.configured?() do
        payload = payload(thread, account.name, owner_handle, status)

        thread.owner_id
        |> Push.live_installations("luft")
        |> Enum.map(&DeliveryWorker.new(%{"registration_id" => &1.id, "payload" => payload}))
        |> Oban.insert_all()
      end
    end

    :ok
  end

  defp payload(%Thread{id: id} = thread, account_handle, owner_handle, status) do
    %{
      "url" => Environment.app_url(path: "/luft/threads/#{id}"),
      "account" => account_handle,
      "user" => owner_handle,
      "thread_id" => id,
      "aps" => %{
        "alert" => %{"title" => Push.thread_title(thread), "body" => body(status)},
        "sound" => "default",
        "thread-id" => id
      }
    }
  end

  # A thread snoozed until a time stays quiet until then; `Tuist.Threads.SnoozeWorker` reminds the owner.
  defp snoozed?(%Thread{snoozed_until: until}), do: until != nil and DateTime.after?(until, DateTime.utc_now())

  defp body("snooze_ended"), do: "Your snooze is over. Tap to pick it up."
  defp body("idle"), do: "Replied. Tap to read it."
  defp body("failed"), do: "Couldn't finish. Tap to see what happened."
  defp body("outcome_unknown"), do: "Stopped while a tool was running. Check it before continuing."
  defp body(_status), do: "Was interrupted. Send a message to continue."
end
