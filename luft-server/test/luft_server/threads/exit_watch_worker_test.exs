defmodule LuftServer.Threads.ExitWatchWorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Repo
  alias LuftServer.Threads.EncryptedBinary
  alias LuftServer.Threads.ExitWatchWorker

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
  end

  test "the wanted lease and encrypted watch persist together and a later park replaces the delivery key" do
    command = Ecto.UUID.generate()

    args = %{
      command_id: command,
      sandbox_id: Ecto.UUID.generate(),
      account_id: 1,
      owner: %{
        owner_session_id: Ecto.UUID.generate(),
        owner_id: 2,
        account_id: 1,
        account_handle: "team"
      },
      session_id: "session",
      signal: "Elixir.Condukt.Signals.ProcessExited",
      key: "old"
    }

    assert :ok = ExitWatchWorker.enqueue(args)
    id = "thread-exit-watch:" <> command

    assert %{rows: [["thread_exit_watch", true, 1]]} =
             Repo.query!("SELECT kind, wanted, want_seq FROM agent_sessions WHERE id=$1", [id])

    assert :ok = ExitWatchWorker.enqueue(%{args | key: "replacement"})
    assert %{rows: [[2]]} = Repo.query!("SELECT want_seq FROM agent_sessions WHERE id=$1", [id])
    %{rows: [[body]]} = Repo.query!("SELECT body FROM agent_objects WHERE key=$1", [id])
    refute body =~ "replacement"
    assert {:ok, json} = EncryptedBinary.load(body)
    assert Jason.decode!(json)["key"] == "replacement"
    assert %{rows: [[1]]} = Repo.query!("SELECT count(*) FROM agent_objects WHERE key=$1", [id])
  end

  test "an old revoked delegation result cannot discard a replacement watch" do
    args = %{command_id: Ecto.UUID.generate(), key: "old"}
    assert :ok = ExitWatchWorker.enqueue(args)
    id = "thread-exit-watch:" <> args.command_id
    %{rows: [[old]]} = Repo.query!("SELECT body FROM agent_objects WHERE key=$1", [id])
    assert :ok = ExitWatchWorker.enqueue(%{args | key: "replacement"})

    ref = make_ref()

    state = %{
      id: id,
      epoch: 1,
      task: %Task{ref: ref, owner: self(), pid: self(), mfa: nil},
      done: false
    }

    assert {:noreply, %{done: false}} =
             ExitWatchWorker.handle_info({ref, {:complete, old, :discard}}, state)

    assert %{rows: [[1]]} = Repo.query!("SELECT count(*) FROM agent_objects WHERE key=$1", [id])
  end

  test "only the live lease epoch can consume a completed watch" do
    args = %{command_id: Ecto.UUID.generate()}
    assert :ok = ExitWatchWorker.enqueue(args)
    id = "thread-exit-watch:" <> args.command_id
    %{rows: [[body]]} = Repo.query!("SELECT body FROM agent_objects WHERE key=$1", [id])

    Repo.query!(
      "UPDATE agent_sessions SET epoch=2, lease_expires_at=CURRENT_TIMESTAMP + interval '20 seconds' WHERE id=$1",
      [id]
    )

    ref = make_ref()

    state = %{
      id: id,
      epoch: 1,
      task: %Task{ref: ref, owner: self(), pid: self(), mfa: nil},
      done: false
    }

    assert {:noreply, %{done: false}} =
             ExitWatchWorker.handle_info({ref, {:complete, body, :discard}}, state)

    ref = make_ref()
    state = %{state | epoch: 2, task: %Task{ref: ref, owner: self(), pid: self(), mfa: nil}}

    assert {:noreply, %{done: true}} =
             ExitWatchWorker.handle_info({ref, {:complete, body, :discard}}, state)

    assert %{rows: [[0]]} = Repo.query!("SELECT count(*) FROM agent_objects WHERE key=$1", [id])
  end
end
