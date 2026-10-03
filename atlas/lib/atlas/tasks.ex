defmodule Atlas.Tasks do
  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Tasks.Task
  alias Atlas.Tasks.Workers.SendDueDate
  alias Atlas.Tasks.Workers.SendReminder
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
      asc: fragment("? IS NULL", task.remind_at),
      asc: task.remind_at,
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

        schedule_reminder!(task)
        schedule_due_date!(task)
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

        changed_reminder? =
          Ecto.Changeset.changed?(changeset, :remind_at) or Ecto.Changeset.changed?(changeset, :assignee_id)

        changed_due_date? =
          Ecto.Changeset.changed?(changeset, :due_on) or Ecto.Changeset.changed?(changeset, :assignee_id)

        changeset =
          if changed_reminder? do
            changeset
            |> Ecto.Changeset.put_change(:reminded_at, nil)
            |> Ecto.Changeset.put_change(:reminder_version, task.reminder_version + 1)
          else
            changeset
          end

        changeset =
          if changed_due_date? do
            changeset
            |> Ecto.Changeset.put_change(:due_notified_at, nil)
            |> Ecto.Changeset.put_change(:due_version, task.due_version + 1)
          else
            changeset
          end

        updated = changeset |> Repo.update() |> unwrap!()
        if changed_reminder? and updated.status == "open", do: schedule_reminder!(updated)
        if changed_due_date? and updated.status == "open", do: schedule_due_date!(updated)
        updated
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

  def snooze_reminder(task, snooze, actor, opts \\ [])

  def snooze_reminder(%Task{status: "open"} = task, snooze, %User{} = actor, opts)
      when snooze in [:tomorrow, :end_of_week, :next_week] do
    remind_at = snooze_remind_at(snooze)

    result =
      Repo.transaction(fn ->
        updated =
          task
          |> Ecto.Changeset.change(
            remind_at: remind_at,
            reminded_at: nil,
            reminder_version: task.reminder_version + 1
          )
          |> Repo.update()
          |> unwrap!()

        schedule_reminder!(updated)
        updated
      end)

    result
    |> normalize_result()
    |> audit_snooze(snooze, actor, opts)
  end

  def snooze_reminder(%Task{}, _snooze, %User{}, _opts), do: {:error, :not_snoozable}

  defp snooze_remind_at(snooze) do
    now = DateTime.utc_now()
    today = DateTime.to_date(now)
    target_date = snooze_target_date(snooze, today)

    target_date
    |> DateTime.new!(~T[09:00:00], "Etc/UTC")
    |> DateTime.truncate(:second)
  end

  defp snooze_target_date(:tomorrow, today), do: Date.add(today, 1)

  defp snooze_target_date(:end_of_week, today) do
    case Date.day_of_week(today) do
      dow when dow <= 4 -> Date.add(today, 5 - dow)
      dow -> Date.add(today, 5 - dow + 7)
    end
  end

  defp snooze_target_date(:next_week, today) do
    case Date.day_of_week(today) do
      1 -> Date.add(today, 7)
      dow -> Date.add(today, 8 - dow)
    end
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

  defp schedule_reminder!(%Task{remind_at: nil}), do: :ok

  defp schedule_reminder!(task) do
    task
    |> then(fn task ->
      SendReminder.new(%{task_id: task.id, reminder_version: task.reminder_version}, scheduled_at: task.remind_at)
    end)
    |> Oban.insert()
    |> unwrap!()
  end

  defp schedule_due_date!(%Task{due_on: nil}), do: :ok

  defp schedule_due_date!(task) do
    scheduled_at = DateTime.new!(task.due_on, ~T[09:00:00], "Etc/UTC")

    task
    |> then(fn task ->
      SendDueDate.new(%{task_id: task.id, due_version: task.due_version}, scheduled_at: scheduled_at)
    end)
    |> Oban.insert()
    |> unwrap!()
  end

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

  defp audit_snooze({:ok, task} = result, snooze, actor, opts) do
    Audit.record("task.reminder_snoozed", %{
      actor_id: actor.id,
      target_type: "task",
      target_id: task.id,
      target_label: task.title,
      interface: Keyword.get(opts, :interface, "dashboard"),
      metadata: %{
        "path" => "/tasks",
        "assignee_id" => task.assignee_id,
        "account_id" => task.account_id,
        "snooze" => Atom.to_string(snooze),
        "remind_at" => DateTime.to_iso8601(task.remind_at)
      }
    })

    result
  end

  defp audit_snooze(error, _snooze, _actor, _opts), do: error
end
