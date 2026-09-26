defmodule Atlas.TasksTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Tasks
  alias Atlas.Tasks.Workers.SendDueDate
  alias Atlas.Tasks.Workers.SendReminder
  alias Atlas.Users.User

  test "rescheduling or reassigning makes an older reminder job harmless" do
    creator = user!("creator")
    next_assignee = user!("next")
    past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    assert {:ok, task} =
             Tasks.create_task(%{title: "Review proposal", assignee_id: creator.id, remind_at: past}, creator)

    old_version = task.reminder_version
    assert {:ok, task} = Tasks.update_task(task, %{assignee_id: next_assignee.id}, creator)
    assert task.reminder_version == old_version + 1

    parent = self()

    poster = fn _app, user_id, text, _blocks, post_opts ->
      send(parent, {:posted, user_id, text, post_opts})
      {:ok, %{}}
    end

    opts = [resolver: fn _, _ -> {:ok, "U123"} end, poster: poster]

    assert :ok = SendReminder.perform_task(task.id, old_version, opts)
    refute_received {:posted, _, _, _}

    assert :ok = SendReminder.perform_task(task.id, task.reminder_version, opts)
    assert_received {:posted, "U123", "Reminder: Review proposal", post_opts}
    assert post_opts[:client_msg_id] == "atlas-task-reminder-#{task.id}-#{task.reminder_version}"

    assert :ok = SendReminder.perform_task(task.id, task.reminder_version, opts)
    refute_received {:posted, _, _, _}
  end

  test "reminder cards include snooze buttons for each preset window" do
    user = user!("reminder-buttons")
    past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    {:ok, task} = Tasks.create_task(%{title: "Ship spec", assignee_id: user.id, remind_at: past}, user)
    parent = self()

    poster = fn _app, _user_id, _text, blocks, _post_opts ->
      send(parent, {:posted_blocks, blocks})
      {:ok, %{}}
    end

    opts = [resolver: fn _, _ -> {:ok, "U000"} end, poster: poster]
    assert :ok = SendReminder.perform_task(task.id, task.reminder_version, opts)
    assert_received {:posted_blocks, blocks}

    actions =
      Enum.find(blocks, fn block -> block["type"] == "actions" end)

    action_ids = actions["elements"] |> Enum.map(& &1["action_id"]) |> Enum.reject(&is_nil/1)
    assert "task_reminder_snooze:tomorrow" in action_ids
    assert "task_reminder_snooze:end_of_week" in action_ids
    assert "task_reminder_snooze:next_week" in action_ids

    view_button = Enum.find(actions["elements"], fn element -> element["text"]["text"] == "View tasks" end)
    assert is_binary(view_button["url"])
    refute Map.has_key?(view_button, "action_id")

    for element <- actions["elements"], element["action_id"] != nil do
      assert element["value"] == task.id
    end
  end

  test "completed tasks do not send reminders" do
    user = user!("owner")
    past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    {:ok, task} = Tasks.create_task(%{title: "Call account", assignee_id: user.id, remind_at: past}, user)
    assert {:ok, _task} = Tasks.complete_task(task, user)

    assert :ok =
             SendReminder.perform_task(task.id, task.reminder_version,
               resolver: fn _, _ -> flunk("should not resolve Slack user") end
             )
  end

  test "due dates send to the assignee and date or assignee edits invalidate older jobs" do
    creator = user!("due-creator")
    next_assignee = user!("due-next")
    today = Date.utc_today()

    assert {:ok, task} =
             Tasks.create_task(%{title: "Prepare notes", assignee_id: creator.id, due_on: today}, creator)

    assert [%Oban.Job{scheduled_at: scheduled_at}] =
             Oban.Testing.all_enqueued(repo: Atlas.Repo, worker: SendDueDate)

    assert DateTime.compare(scheduled_at, DateTime.new!(today, ~T[09:00:00], "Etc/UTC")) == :eq

    old_version = task.due_version
    assert {:ok, task} = Tasks.update_task(task, %{assignee_id: next_assignee.id}, creator)
    assert task.due_version == old_version + 1

    parent = self()

    poster = fn _app, user_id, text, blocks, post_opts ->
      send(parent, {:posted_due, user_id, text, blocks, post_opts})
      {:ok, %{}}
    end

    opts = [resolver: fn _, _ -> {:ok, "U456"} end, poster: poster]

    assert :ok = SendDueDate.perform_task(task.id, old_version, opts)
    refute_received {:posted_due, _, _, _, _}

    assert :ok = SendDueDate.perform_task(task.id, task.due_version, opts)
    assert_received {:posted_due, "U456", "Due today: Prepare notes", blocks, post_opts}
    assert inspect(blocks) =~ "Task due today"
    assert post_opts[:client_msg_id] == "atlas-task-due-#{task.id}-#{task.due_version}"

    assert :ok = SendDueDate.perform_task(task.id, task.due_version, opts)
    refute_received {:posted_due, _, _, _, _}
  end

  test "completed tasks and future due dates do not notify" do
    user = user!("due-owner")
    today = Date.utc_today()
    tomorrow = Date.add(today, 1)
    {:ok, task} = Tasks.create_task(%{title: "Plan launch", assignee_id: user.id, due_on: tomorrow}, user)

    assert :ok =
             SendDueDate.perform_task(task.id, task.due_version,
               resolver: fn _, _ -> flunk("should not resolve Slack user") end
             )

    {:ok, task} = Tasks.update_task(task, %{due_on: today}, user)
    assert {:ok, _task} = Tasks.complete_task(task, user)

    assert :ok =
             SendDueDate.perform_task(task.id, task.due_version,
               resolver: fn _, _ -> flunk("should not resolve Slack user") end
             )
  end

  test "past due dates are described as overdue" do
    user = user!("overdue-owner")
    yesterday = Date.utc_today() |> Date.add(-1)
    {:ok, task} = Tasks.create_task(%{title: "Send report", assignee_id: user.id, due_on: yesterday}, user)
    parent = self()

    assert :ok =
             SendDueDate.perform_task(task.id, task.due_version,
               resolver: fn _, _ -> {:ok, "U789"} end,
               poster: fn _app, _user_id, text, _blocks, _post_opts ->
                 send(parent, {:posted_overdue, text})
                 {:ok, %{}}
               end
             )

    assert_received {:posted_overdue, "Overdue: Send report"}
  end

  test "snoozing a reminder bumps its version, updates remind_at, and schedules a new job" do
    user = user!("snooze-owner")
    past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

    {:ok, task} = Tasks.create_task(%{title: "Follow up", assignee_id: user.id, remind_at: past}, user)
    original_version = task.reminder_version

    assert {:ok, snoozed} = Tasks.snooze_reminder(task, :tomorrow, user)
    assert snoozed.reminder_version == original_version + 1
    assert is_nil(snoozed.reminded_at)

    tomorrow = Date.utc_today() |> Date.add(1)
    assert DateTime.to_date(snoozed.remind_at) == tomorrow
    assert DateTime.to_time(snoozed.remind_at) == ~T[09:00:00]

    scheduled_jobs =
      Oban.Testing.all_enqueued(repo: Atlas.Repo, worker: SendReminder)
      |> Enum.filter(fn %Oban.Job{args: args} ->
        args["task_id"] == task.id and args["reminder_version"] == snoozed.reminder_version
      end)

    assert [%Oban.Job{scheduled_at: scheduled_at}] = scheduled_jobs
    assert DateTime.compare(scheduled_at, snoozed.remind_at) == :eq
  end

  test "snoozing rejects tasks that are not open" do
    user = user!("snooze-completed")
    past = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)
    {:ok, task} = Tasks.create_task(%{title: "Ping account", assignee_id: user.id, remind_at: past}, user)
    {:ok, task} = Tasks.complete_task(task, user)

    assert {:error, :not_snoozable} = Tasks.snooze_reminder(task, :tomorrow, user)
  end

  test "filters tasks by search text and stores the due date" do
    user = user!("search-owner")

    assert {:ok, matching} =
             Tasks.create_task(
               %{title: "Review proposal", assignee_id: user.id, due_on: ~D[2026-10-01]},
               user
             )

    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account:search-#{System.unique_integer([:positive])}",
        name: "Example Industries",
        segment: :lead
      })
      |> Repo.insert!()

    assert {:ok, other} =
             Tasks.create_task(
               %{title: "Call customer", assignee_id: user.id, account_id: account.id},
               user
             )

    assert matching.due_on == ~D[2026-10-01]
    assert [%{id: id}] = Tasks.list_tasks(query: "proposal", status: "open")
    assert id == matching.id
    assert [%{id: ^id}] = Tasks.list_tasks(query: "PROPOSAL", status: "open")
    assert [%{id: other_id}] = Tasks.list_tasks(query: "Industries", status: "open")
    assert other_id == other.id
    assert [] = Tasks.list_tasks(query: "_", status: "open")
    assert [_task] = Tasks.list_tasks(status: "open", limit: 1)
  end

  test "task text limits return changeset errors" do
    user = user!("text-owner")

    assert {:error, changeset} =
             Tasks.create_task(%{title: String.duplicate("x", 256), assignee_id: user.id}, user)

    assert errors_on(changeset).title

    assert {:error, changeset} =
             Tasks.create_task(%{title: "Valid", description: String.duplicate("x", 2001), assignee_id: user.id}, user)

    assert errors_on(changeset).description
  end

  defp user!(name) do
    %User{}
    |> User.changeset(%{email: "#{name}-#{System.unique_integer([:positive])}@tuist.dev", name: name})
    |> Repo.insert!()
  end
end
