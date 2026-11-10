defmodule Atlas.Tasks do
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Tasks.Task
  alias Atlas.Users.User

  def list_tasks(opts \\ []) do
    Task
    |> maybe_filter(:assignee_id, opts[:assignee_id])
    |> maybe_filter(:account_id, opts[:account_id])
    |> maybe_exclude(:assignee_id, opts[:exclude_assignee_id])
    |> maybe_exclude(:account_id, opts[:exclude_account_id])
    |> maybe_filter(:status, opts[:status])
    |> maybe_search(opts[:query])
    |> order_by([task],
      asc: fragment("? IS NULL", task.due_on),
      asc: task.due_on,
      desc: task.inserted_at
    )
    |> maybe_limit(opts[:limit])
    |> preload([:assignee, :account])
    |> Repo.all()
  end

  def get_task(id), do: Task |> preload([:assignee, :account]) |> Repo.get(id)

  def change_task(task \\ %Task{}, attrs \\ %{}), do: Task.changeset(task, attrs)

  def create_task(attrs, %User{} = actor, opts \\ []) do
    result =
      Repo.transaction(fn ->
        task =
          %Task{created_by_id: actor.id}
          |> Task.changeset(attrs)
          |> Repo.insert()
          |> unwrap!()

        task
      end)

    result
    |> normalize_result()
    |> audit_result("task.created", actor, opts)
  end

  def update_task(%Task{} = task, attrs, %User{} = actor, opts \\ []) do
    result =
      Repo.transaction(fn ->
        changeset = Task.changeset(task, attrs)
        updated = changeset |> Repo.update() |> unwrap!()
        Repo.preload(updated, [:assignee, :account], force: true)
      end)

    result
    |> normalize_result()
    |> audit_result("task.updated", actor, opts)
  end

  def complete_task(task, actor, opts \\ [])

  def complete_task(%Task{status: "open"} = task, %User{} = actor, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    task
    |> Ecto.Changeset.change(status: "completed", completed_at: now)
    |> Repo.update()
    |> audit_result("task.completed", actor, opts)
  end

  def complete_task(%Task{}, %User{}, _opts), do: {:error, :already_completed}

  def delete_task(%Task{} = task, %User{} = actor, opts \\ []) do
    task
    |> Repo.delete()
    |> audit_result("task.deleted", actor, opts)
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, field, value), do: where(query, [task], field(task, ^field) == ^value)

  defp maybe_exclude(query, _field, nil), do: query

  defp maybe_exclude(query, field, value) do
    where(query, [task], is_nil(field(task, ^field)) or field(task, ^field) != ^value)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    search = String.trim(search)

    if search == "" do
      query
    else
      escaped =
        search
        |> String.replace("\\", "\\\\")
        |> String.replace("%", "\\%")
        |> String.replace("_", "\\_")

      pattern = "%#{escaped}%"

      query
      |> join(:left, [task], account in assoc(task, :account))
      |> where(
        [task, account],
        ilike(task.title, ^pattern) or ilike(task.description, ^pattern) or ilike(account.name, ^pattern)
      )
    end
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)

  defp normalize_result({:ok, task}), do: {:ok, task}
  defp normalize_result({:error, reason}), do: {:error, reason}

  defp audit_result({:ok, task} = result, action, actor, opts) do
    Audit.record(action, %{
      actor_id: actor.id,
      target_type: "task",
      target_id: task.id,
      target_label: task.title,
      interface: Keyword.get(opts, :interface, "dashboard"),
      metadata: %{
        "path" => "/tasks",
        "assignee_id" => task.assignee_id,
        "account_id" => task.account_id,
        "due_on" => task.due_on && Date.to_iso8601(task.due_on)
      }
    })

    result
  end

  defp audit_result(error, _action, _actor, _opts), do: error
end
