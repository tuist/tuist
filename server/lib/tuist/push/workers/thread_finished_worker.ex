defmodule Tuist.Push.Workers.ThreadFinishedWorker do
  @moduledoc """
  Tells a thread's owner on their Tuist Guild devices that the thread stopped
  working (it replied, failed or was stopped), one `DeliveryWorker` job per
  device. Enqueued by `Tuist.Push.notify_thread_finished/2` in the transaction
  that sets the status.

  The alert shows a fixed line for the status and, once the agent named the
  thread, its title; never message content. A thread starts titled with the
  start of its first message, so until it's renamed the alert says "Your
  thread". `url` is the thread's Guild web URL on this server, which Guild
  opens; `account` is the handle of the account that owns the thread, which
  Guild selects first; and `user` is the owner's handle, so Guild opens it in
  the owner's profile. Guild registers only Apple devices (see
  `Tuist.Push.register/4`), so it sends nothing when APNs isn't configured.
  """

  use Oban.Worker, queue: :push, max_attempts: 3

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Push
  alias Tuist.Push.APNs
  alias Tuist.Push.Workers.DeliveryWorker
  alias Tuist.Repo
  alias Tuist.Threads.Thread

  @max_title_length 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => thread_id, "status" => status}}) do
    with %Thread{} = thread <- Repo.get(Thread, thread_id),
         {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
         %{account: %{name: owner_handle}} <- Accounts.get_user_by_id(thread.owner_id) do
      if APNs.configured?() do
        payload = payload(thread, account.name, owner_handle, status)

        thread.owner_id
        |> Push.live_installations("guild")
        |> Enum.map(&DeliveryWorker.new(%{"registration_id" => &1.id, "payload" => payload}))
        |> Oban.insert_all()
      end
    end

    :ok
  end

  defp payload(%Thread{id: id} = thread, account_handle, owner_handle, status) do
    %{
      "url" => Environment.app_url(path: "/guild/threads/#{id}"),
      "account" => account_handle,
      "user" => owner_handle,
      "thread_id" => id,
      "aps" => %{
        "alert" => %{"title" => title(thread), "body" => body(status)},
        "sound" => "default",
        "thread-id" => id
      }
    }
  end

  # `Tuist.Threads` titles a new thread with the start of its first message;
  # only a title the agent gave it is safe to show on a lock screen.
  defp title(%Thread{title: title, goal: goal}) do
    title = title |> to_string() |> String.trim()

    if title == "" or title == String.trim(String.slice(to_string(goal), 0, 80)) do
      "Your thread"
    else
      String.slice(title, 0, @max_title_length)
    end
  end

  defp body("idle"), do: "Replied. Tap to read it."
  defp body("failed"), do: "Couldn't finish. Tap to see what happened."
  defp body("outcome_unknown"), do: "Stopped while a tool was running. Check it before continuing."
  defp body(_status), do: "Was interrupted. Send a message to continue."
end
