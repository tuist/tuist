defmodule Tuist.Threads.WorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Agents.Lease
  alias Tuist.Threads
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Run
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.Worker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_global

  setup do
    stub(Provider, :validate_model, fn _, "chatgpt", "selected-model" -> :ok end)
    :ok
  end

  test "an inference job an earlier release enqueued hands its run to the thread's session" do
    user = AccountsFixtures.user_fixture()
    {:ok, thread} = Threads.create(user, user.account, request("From the old release"))
    # As the old release left it: running at attempt 2, with no session row.
    run = Repo.update!(Ecto.Changeset.change(Repo.one!(Run), status: "running", attempt: 2))
    Repo.delete_all(from(s in "agent_sessions", where: s.id == ^thread.id))

    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})

    [%{epoch: epoch}] = Enum.filter(Lease.claim("test-host", 100), &(&1.id == thread.id))
    assert epoch > run.attempt
    assert {:ok, {claimed, _}} = Threads.claim(run.id, epoch)
    assert claimed.attempt == epoch
  end

  test "Ship receives the claimed attempt and an uncertain result is never replayed" do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> {:ok, []} end)
    {:ok, thread} = Threads.create(user, user.account, request("Ship the review"))

    approval =
      Repo.insert!(%Approval{
        thread_id: thread.id,
        account_id: user.account.id,
        request_id: Ecto.UUID.generate(),
        repository: "example/repo",
        head_sha: String.duplicate("a", 40),
        diff: "+ reviewed",
        target_branch: "threads/example",
        mode: :branch,
        status: :approved,
        approved_by_id: user.id,
        approved_at: DateTime.utc_now(:second)
      })

    run = Repo.update!(Ecto.Changeset.change(Repo.one!(Run), kind: "ship", approval_id: approval.id))
    test = self()

    expect(Shipping, :execute, fn bound_thread, bound_approval, bound_run ->
      send(test, {:ship_attempt, bound_thread.id, bound_approval, bound_run})
      {:error, :shipping_uncertain}
    end)

    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert_receive {:ship_attempt, thread_id, bound_approval, bound_run}
    assert thread_id == thread.id
    assert bound_approval.id == approval.id
    assert bound_approval.status == :executing
    assert bound_run.id == run.id
    assert bound_run.attempt == 1
    assert bound_run.status == "running"
    assert Repo.reload!(run).status == "outcome_unknown"
    assert :ok = Threads.recover()
    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    refute_receive {:ship_attempt, _, _, _}
    assert Repo.reload!(run).status == "outcome_unknown"
  end

  defp request(body),
    do: %{"content" => body, "request_id" => Ecto.UUID.generate(), "provider" => "chatgpt", "model" => "selected-model"}
end
