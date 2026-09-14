defmodule Tuist.Runners.Workers.GitLabPollWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Repo
  alias Tuist.Runners.GitLab
  alias Tuist.Runners.GitLab.Connection
  alias Tuist.Runners.Workers.GitLabPollWorker

  test "successful and rejected jobs schedule another poll without occupying a worker" do
    connection = %Connection{id: 1}
    stub(GitLab, :get_connection, fn 1 -> connection end)
    stub(GitLab, :record_poll_result, fn ^connection, _ -> :ok end)

    for result <- [{:ok, 0}, {:ok, 1}, {:error, :invalid_job_tags}] do
      expect(GitLab, :poll, fn ^connection -> result end)

      assert {:snooze, 5} =
               GitLabPollWorker.perform(%Oban.Job{args: %{"connection_id" => 1}, inserted_at: DateTime.utc_now()})
    end

    assert GitLabPollWorker.new(%{connection_id: 1}).changes.queue == "runner_gitlab"
  end

  test "inactive connections, upstream errors and expired windows stop polling" do
    connection = %Connection{id: 1}
    stub(GitLab, :get_connection, fn 1 -> connection end)
    stub(GitLab, :record_poll_result, fn ^connection, _ -> :ok end)

    for result <- [{:ok, :inactive}, {:error, :unauthorized}, {:error, :transport}] do
      expect(GitLab, :poll, fn ^connection -> result end)
      assert :ok = GitLabPollWorker.perform(%Oban.Job{args: %{"connection_id" => 1}, inserted_at: DateTime.utc_now()})
    end

    expect(GitLab, :poll, fn ^connection -> {:ok, 0} end)

    assert :ok =
             GitLabPollWorker.perform(%Oban.Job{
               args: %{"connection_id" => 1},
               inserted_at: DateTime.add(DateTime.utc_now(), -55)
             })
  end

  test "cron replaces a stale executing poll after a server restart while preserving a fresh poll" do
    stale_time = DateTime.add(DateTime.utc_now(), -180, :second)

    {:ok, stale} =
      %{connection_id: 1}
      |> GitLabPollWorker.new()
      |> Ecto.Changeset.change(state: "executing", inserted_at: stale_time, attempted_at: stale_time)
      |> Oban.insert()

    {:ok, fresh} = %{connection_id: 2} |> GitLabPollWorker.new() |> Oban.insert()
    stub(GitLab, :purge_expired_payloads, fn -> :ok end)
    stub(GitLab, :list_pollable_connections, fn -> [%Connection{id: 1}, %Connection{id: 2}] end)

    assert :ok = GitLabPollWorker.perform(%Oban.Job{args: %{}})

    jobs = Repo.all(Oban.Job)
    assert Enum.count(jobs, &(&1.args == %{"connection_id" => 1} and &1.id != stale.id)) == 1
    assert jobs |> Enum.filter(&(&1.args == %{"connection_id" => 2})) |> Enum.map(& &1.id) == [fresh.id]
  end
end
