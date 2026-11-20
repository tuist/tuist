defmodule LuftServer.Notifications do
  @moduledoc "Durable conversation notification hooks; call inside the transaction that changes the thread."
  alias LuftServer.Notifications.LiveActivities
  alias LuftServer.Notifications.ThreadFinishedWorker

  def thread_changed(%{owner_id: owner}), do: LiveActivities.thread_changed(owner)

  def notify_thread_finished(%{id: id, revision: revision} = thread, status) do
    {:ok, _} =
      %{"thread_id" => id, "revision" => revision, "status" => status}
      |> ThreadFinishedWorker.new()
      |> Oban.insert()

    thread_changed(thread)
  end
end
