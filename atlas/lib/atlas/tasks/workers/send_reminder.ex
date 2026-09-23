defmodule Atlas.Tasks.Workers.SendReminder do
  use Oban.Worker, queue: :default, max_attempts: 5

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Tasks.SlackNotifier
  alias Atlas.Tasks.Task
  alias Atlas.Users.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id, "reminder_version" => version}}) do
    perform_task(task_id, version)
  end

  def perform_task(task_id, version, opts \\ []) do
    task = Task |> Repo.get(task_id) |> preload_task()

    if sendable?(task, version) do
      with {:ok, _response} <- SlackNotifier.send(task, :reminder, opts) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {updated, _} =
          Task
          |> where([task], task.id == ^task_id and task.reminder_version == ^version and task.status == "open")
          |> where([task], is_nil(task.reminded_at))
          |> Repo.update_all(set: [reminded_at: now])

        if updated == 1 do
          Audit.record("task.reminder_sent", %{
            interface: "worker",
            target_type: "task",
            target_id: task.id,
            target_label: task.title,
            metadata: %{"path" => "/tasks", "assignee_id" => task.assignee_id, "account_id" => task.account_id}
          })
        end

        :ok
      end
    else
      :ok
    end
  end

  defp preload_task(nil), do: nil
  defp preload_task(task), do: Repo.preload(task, [:assignee, :account])

  defp sendable?(
         %Task{
           status: "open",
           assignee: %User{},
           reminded_at: nil,
           remind_at: %DateTime{} = remind_at,
           reminder_version: version
         },
         version
       ) do
    DateTime.compare(remind_at, DateTime.utc_now()) != :gt
  end

  defp sendable?(_, _), do: false
end
