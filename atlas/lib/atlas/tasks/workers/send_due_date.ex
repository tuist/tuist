defmodule Atlas.Tasks.Workers.SendDueDate do
  use Oban.Worker, queue: :default, max_attempts: 5

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Tasks.SlackNotifier
  alias Atlas.Tasks.Task
  alias Atlas.Users.User

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id, "due_version" => version}}) do
    perform_task(task_id, version)
  end

  def perform_task(task_id, version, opts \\ []) do
    task = Task |> Repo.get(task_id) |> preload_task()

    if sendable?(task, version) do
      with {:ok, _response} <- SlackNotifier.send(task, :due_date, opts) do
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {updated, _} =
          Task
          |> where([task], task.id == ^task_id and task.due_version == ^version and task.status == "open")
          |> where([task], is_nil(task.due_notified_at))
          |> Repo.update_all(set: [due_notified_at: now])

        if updated == 1 do
          Audit.record("task.due_notification_sent", %{
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
         %Task{status: "open", assignee: %User{}, due_notified_at: nil, due_on: %Date{} = due_on, due_version: version},
         version
       ) do
    Date.compare(due_on, Date.utc_today()) != :gt
  end

  defp sendable?(_, _), do: false
end
