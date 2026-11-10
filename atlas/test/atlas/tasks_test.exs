defmodule Atlas.TasksTest do
  use Atlas.DataCase, async: true

  alias Atlas.Accounts.Account
  alias Atlas.Repo
  alias Atlas.Tasks
  alias Atlas.Users.User

  test "creates, updates, completes, and deletes a task without enqueuing a notification" do
    user = user!("owner")

    assert {:ok, task} =
             Tasks.create_task(%{title: "Review proposal", assignee_id: user.id, due_on: ~D[2026-10-01]}, user)

    assert task.due_on == ~D[2026-10-01]
    assert [] = Oban.Testing.all_enqueued(repo: Atlas.Repo)

    assert {:ok, updated} = Tasks.update_task(task, %{title: "Review revised proposal"}, user)
    assert updated.title == "Review revised proposal"
    assert {:ok, completed} = Tasks.complete_task(updated, user)
    assert completed.status == "completed"
    assert {:ok, _deleted} = Tasks.delete_task(completed, user)
    assert Tasks.get_task(task.id) == nil
  end

  test "filters tasks by search text and stores the due date" do
    user = user!("search-owner")

    assert {:ok, matching} =
             Tasks.create_task(%{title: "Review proposal", assignee_id: user.id, due_on: ~D[2026-10-01]}, user)

    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account:search-#{System.unique_integer([:positive])}",
        name: "Example Industries",
        segment: :lead
      })
      |> Repo.insert!()

    assert {:ok, other} =
             Tasks.create_task(%{title: "Call customer", assignee_id: user.id, account_id: account.id}, user)

    assert matching.due_on == ~D[2026-10-01]
    assert [%{id: id}] = Tasks.list_tasks(query: "proposal", status: "open")
    assert id == matching.id
    assert [%{id: ^id}] = Tasks.list_tasks(query: "PROPOSAL", status: "open")
    assert [%{id: other_id}] = Tasks.list_tasks(query: "Industries", status: "open")
    assert other_id == other.id
    assert [] = Tasks.list_tasks(query: "_", status: "open")
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
