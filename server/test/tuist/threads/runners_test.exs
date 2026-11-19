defmodule Tuist.Threads.RunnersTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Threads
  alias Tuist.Threads.Provider
  alias Tuist.Threads.RecoveryWorker
  alias Tuist.Threads.Runner
  alias Tuist.Threads.RunnerRequest
  alias Tuist.Threads.Runners
  alias Tuist.Threads.RunnerSandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, runner, token} = Runners.register(user, %{"name" => "studio-macbook", "platform" => "macos"})
    %{user: user, runner: runner, token: token}
  end

  test "a thread's call reaches the runner's poll and gets its answer", %{user: user, runner: runner} do
    {:ok, other, _token} = Runners.register(user, %{"name" => "linux-box", "platform" => "linux"})
    caller = Task.async(fn -> Runners.call(runner.id, "read_file", %{"path" => "/src/README.md"}, 5_000) end)

    # Another runner never sees it.
    assert Runners.poll(other, %{}, 200) == []
    assert [%{"op" => "read_file", "path" => "/src/README.md", "id" => id}] = Runners.poll(runner, %{}, 3_000)
    assert {:error, :not_found} = Runners.respond(other, id, %{"ok" => true, "result" => %{"text" => "no"}})

    assert :ok = Runners.respond(runner, id, %{"ok" => true, "result" => %{"text" => "hello"}})
    assert {:ok, %{"text" => "hello"}} = Task.await(caller)
    # Answered once; the caller removed it.
    assert {:error, :not_found} = Runners.respond(runner, id, %{"ok" => true})
    refute Repo.exists?(RunnerRequest)
  end

  test "the runner's errors reach the caller, and an offline runner times out", %{runner: runner} do
    caller = Task.async(fn -> Runners.call(runner.id, "exec", %{"command" => "true"}, 5_000) end)
    [%{"id" => id}] = Runners.poll(runner, %{}, 3_000)
    :ok = Runners.respond(runner, id, %{"ok" => false, "error" => "Terminal access is off on this runner"})
    assert {:error, "Terminal access is off on this runner"} = Task.await(caller)

    assert {:error, :timeout} = Runners.call(runner.id, "info", %{}, 300)
    refute Repo.exists?(RunnerRequest)
  end

  test "a claim the daemon never received goes back to the queue", %{runner: runner} do
    caller = Task.async(fn -> Runners.call(runner.id, "read_file", %{"path" => "/src/a"}, 10_000) end)
    other = Task.async(fn -> Runners.call(runner.id, "exec", %{"command" => "make"}, 10_000) end)
    claimed = Runners.poll(runner, %{}, 3_000) ++ Runners.poll(runner, %{}, 3_000)
    %{"id" => lost} = Enum.find(claimed, &(&1["op"] == "read_file"))
    %{"id" => running} = Enum.find(claimed, &(&1["op"] == "exec"))

    # Recently claimed requests are left alone: their poll may still be on its way.
    assert Runners.poll(runner, %{"in_flight" => [running]}, 0) == []

    # Claimed a while ago: what the daemon lists keeps running, what it doesn't comes back.
    past = DateTime.add(DateTime.utc_now(:second), -30)
    Repo.update_all(RunnerRequest, set: [claimed_at: past])
    assert [%{"id" => ^lost, "op" => "read_file"}] = Runners.poll(runner, %{"in_flight" => [running, "junk"]}, 0)

    :ok = Runners.respond(runner, lost, %{"ok" => true, "result" => %{"text" => "a"}})
    :ok = Runners.respond(runner, running, %{"ok" => true, "result" => %{"exit_code" => 0}})
    assert {:ok, %{"text" => "a"}} = Task.await(caller)
    assert {:ok, %{"exit_code" => 0}} = Task.await(other)
  end

  test "the sandbox sends text with NUL as base64, which jsonb can store", %{runner: runner} do
    {:ok, sandbox} = RunnerSandbox.init(runner_id: runner.id, cwd: "/src")
    writer = Task.async(fn -> RunnerSandbox.write_file(sandbox, "list", "a\0b") end)

    assert [%{"op" => "write_file", "path" => "/src/list", "base64" => "YQBi", "id" => id} = request] =
             Runners.poll(runner, %{}, 3_000)

    refute Map.has_key?(request, "text")
    :ok = Runners.respond(runner, id, %{"ok" => true, "result" => %{"bytes" => 3}})
    assert :ok = Task.await(writer)
  end

  test "the sandbox lists a folder through the runner, without its shell", %{runner: runner} do
    {:ok, sandbox} = RunnerSandbox.init(runner_id: runner.id, cwd: "/src")
    lister = Task.async(fn -> RunnerSandbox.list_dir(sandbox, "app") end)
    [%{"op" => "list_dir", "path" => "/src/app", "id" => id}] = Runners.poll(runner, %{}, 3_000)

    entries = [%{"name" => "Sources", "kind" => "directory"}, %{"name" => "link", "kind" => "symlink"}]
    :ok = Runners.respond(runner, id, %{"ok" => true, "result" => %{"entries" => entries}})

    assert {:ok, [%{name: "Sources", type: :directory}, %{name: "link", type: :file}]} = Task.await(lister)
  end

  test "an answer that isn't base64 is an error, not a crash", %{runner: runner} do
    {:ok, sandbox} = RunnerSandbox.init(runner_id: runner.id, cwd: "/src")
    reader = Task.async(fn -> RunnerSandbox.read_file(sandbox, "logo.png") end)
    [%{"id" => id}] = Runners.poll(runner, %{}, 3_000)
    :ok = Runners.respond(runner, id, %{"ok" => true, "result" => %{"base64" => "not base64!"}})
    assert {:error, :invalid_response} = Task.await(reader)
  end

  test "the minute's recovery deletes requests whose caller died", %{runner: runner} do
    insert = fn expires_at ->
      Repo.insert!(%RunnerRequest{
        runner_id: runner.id,
        op: "exec",
        payload: %{"command" => "make"},
        expires_at: expires_at
      })
    end

    now = DateTime.utc_now(:second)
    expired = insert.(DateTime.add(now, -5))
    waiting = insert.(DateTime.add(now, 60))

    assert :ok = RecoveryWorker.perform(%Oban.Job{args: %{}})
    refute Repo.get(RunnerRequest, expired.id)
    assert Repo.get(RunnerRequest, waiting.id)
  end

  test "polling records what the runner allows and that it is online", %{user: user, runner: runner} do
    refute Runners.online?(runner)
    Runners.poll(runner, %{"folders" => ["/src", 3], "terminal" => true, "display" => "yes", "secret" => "x"}, 0)

    [listed] = Runners.list(user)
    assert Runners.online?(listed)

    assert %{folders: ["/src"], terminal: true, display: false, portals: false} =
             Runners.serialize(listed).capabilities
             |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)
             |> Map.take([:folders, :terminal, :display, :portals])
  end

  test "a revoked runner's secret stops working and threads can't choose it", %{
    user: user,
    runner: runner,
    token: token
  } do
    stranger = AccountsFixtures.user_fixture()
    assert {:ok, _} = Runners.authenticate(token)
    assert {:error, :not_found} = Runners.revoke(stranger, runner.id)
    assert {:error, :runner_not_found} = Runners.usable(stranger, runner.id)

    assert :ok = Runners.revoke(user, runner.id)
    assert {:error, :unauthorized} = Runners.authenticate(token)
    assert {:error, :runner_not_found} = Runners.usable(user, runner.id)
    assert Runners.list(user) == []
  end

  test "threads run on their owner's runners only", %{user: user, runner: runner} do
    stub(Provider, :validate_model, fn _, _, _ -> :ok end)
    stranger = AccountsFixtures.user_fixture()
    {:ok, theirs, _} = Runners.register(stranger, %{"name" => "theirs", "platform" => "macos"})

    request = fn runner_id ->
      %{
        "content" => "Look around",
        "request_id" => Ecto.UUID.generate(),
        "provider" => "chatgpt",
        "model" => "m",
        "runner_id" => runner_id
      }
    end

    # A runner the server hasn't heard from in the last minute is refused,
    # rather than leaving every tool call to time out.
    first = request.(runner.id)
    assert {:error, :runner_offline} = Threads.create(user, user.account, first)

    Runners.poll(runner, %{}, 0)
    assert {:ok, thread} = Threads.create(user, user.account, first)
    assert Threads.serialize(thread).runner_id == runner.id

    # A retry of the thread already created still answers with it once the runner goes away.
    Repo.update_all(Runner, set: [last_seen_at: DateTime.add(DateTime.utc_now(), -120)])
    assert {:ok, %{id: same}} = Threads.create(user, user.account, first)
    assert same == thread.id

    # And once the runner is removed; a new thread on it is refused.
    :ok = Runners.revoke(user, runner.id)
    assert {:ok, %{id: ^same}} = Threads.create(user, user.account, first)
    assert {:error, :runner_not_found} = Threads.create(user, user.account, request.(runner.id))
    assert {:error, :runner_not_found} = Threads.create(user, user.account, request.(theirs.id))
    assert {:error, :runner_not_found} = Threads.create(user, user.account, request.("not-a-uuid"))
  end

  test "registration needs a name and a known platform", %{user: user} do
    assert {:error, :invalid} = Runners.register(user, %{"name" => "  ", "platform" => "macos"})
    assert {:error, :invalid} = Runners.register(user, %{"name" => "box", "platform" => "beos"})
  end
end
