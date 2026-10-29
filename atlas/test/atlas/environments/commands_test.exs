defmodule Atlas.Environments.CommandsTest do
  use Atlas.DataCase, async: true

  import Atlas.EnvironmentFixtures
  import Atlas.OrbitFixtures

  alias Atlas.Environments
  alias Atlas.Environments.Command
  alias Atlas.Environments.Commands
  alias Atlas.Orbit
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Tools
  alias Atlas.Repo

  setup do
    environment_fixture()
  end

  test "only the bound native client and owner see, claim or complete commands", c do
    command = command_fixture(c)
    assert {:error, :not_found} = Commands.queued(user_fixture(), c.client_id, c.environment.id)
    assert {:error, :not_found} = Commands.queued(c.user, Ecto.UUID.generate(), c.environment.id)
    assert {:ok, [envelope]} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert envelope.arguments == %{"path" => "README.md", "project_id" => c.project_id}

    assert Map.keys(envelope) |> Enum.sort() == [
             :arguments,
             :digest,
             :execution_timeout_seconds,
             :id,
             :tool
           ]

    assert {:error, :not_found} =
             Commands.claim(c.user, Ecto.UUID.generate(), c.environment.id, command.id, %{
               "digest" => command.digest
             })

    claimed = claim_fixture(c, command)

    assert {:error, :not_found} =
             Commands.complete(user_fixture(), c.client_id, c.environment.id, command.id, result(claimed))

    assert {:error, :not_found} =
             Commands.complete(c.user, Ecto.UUID.generate(), c.environment.id, command.id, result(claimed))
  end

  test "coding freezes worktree identity, replays known writes and fences all mutations after an unknown edit", c do
    params = %{registration(c.project_id) | "projects" => [%{"id" => c.project_id, "name" => "Code", "coding" => true}]}
    {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, params)
    {:ok, _} = Environments.renew(c.user, c.client_id, c.environment.id, Ecto.UUID.generate())
    args = %{"path" => "file", "content" => "new contents"}
    command = command_fixture(c, "write", args)

    assert JSON.decode!(command.arguments) ==
             Map.merge(args, %{"project_id" => c.project_id, "thread_id" => c.thread.id, "title" => c.thread.title})

    claimed = claim_fixture(c, command)
    assert {:ok, _} = Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))
    assert {:ok, "known result"} = Tools.call(c.run.id, 0, "write", args)
    assert {:ok, "known result"} = Tools.call(c.run.id, 0, "write", args)
    assert Repo.aggregate(Command, :count) == 1
    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)

    edit = command_fixture(c, "edit", %{"path" => "file", "edits" => [%{"oldText" => "new", "newText" => "changed"}]})
    _ = claim_fixture(c, edit)
    edit |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1)) |> Repo.update!()
    Commands.sweep()
    assert Repo.reload!(edit).status == "unknown"
    assert {:error, _} = Tools.call(c.run.id, 0, "write", %{"path" => "other", "content" => "unsafe retry"})
    assert {:error, _} = Tools.call(c.run.id, 0, "bash", %{"command" => "echo unsafe > other"})
    assert Repo.aggregate(Command, :count) == 2
  end

  test "bash uses durable tickets, owner progress and cancellation just like terminal", c do
    params = %{registration(c.project_id) | "projects" => [%{"id" => c.project_id, "name" => "Code", "coding" => true}]}
    {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, params)
    {:ok, _} = Environments.renew(c.user, c.client_id, c.environment.id, Ecto.UUID.generate())
    assert {:ok, ticket} = Tools.call(c.run.id, 0, "bash", %{"command" => "make test", "timeout" => 90})
    assert {:ok, ^ticket} = Tools.call(c.run.id, 0, "bash", %{"command" => "make test", "timeout" => 90})
    assert {:ok, [envelope]} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert envelope.arguments["thread_id"] == c.thread.id
    assert envelope.arguments["timeout"] == 90
    claimed = claim_fixture(c, Repo.get!(Command, envelope.id))

    assert {:ok, %{received: true, cancel_requested: false}} =
             Commands.progress(c.user, c.client_id, c.environment.id, envelope.id, %{
               "claim_token" => claimed.claim_token,
               "sequence" => 1,
               "output" => "tests running"
             })

    assert {:ok, %{commands: [job]}} = Commands.list(c.user, c.thread.id)
    assert job.output == "tests running"
    assert {:ok, _} = Commands.cancel(c.user, c.thread.id, envelope.id, %{"digest" => envelope.digest})

    assert {:ok, _} =
             Commands.complete(c.user, c.client_id, c.environment.id, envelope.id, %{
               "claim_token" => claimed.claim_token,
               "success" => false,
               "output" => "stopped"
             })

    assert {:ok, %{commands: [job]}} = Commands.list(c.user, c.thread.id)
    assert job.status == "settled" and job.success == false and job.cancel_requested
    assert Repo.aggregate(Command, :count) == 1
  end

  test "opted-in terminal commands are immediately claimable only by their exact immutable digest", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    assert command.status == "queued"
    assert {:ok, [envelope]} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert envelope.arguments == %{"command" => "pwd", "project_id" => c.project_id}
    assert envelope.execution_timeout_seconds == 1_800

    assert {:error, :command_digest_mismatch} =
             Commands.claim(c.user, c.client_id, c.environment.id, command.id, %{
               "digest" => String.duplicate("a", 64)
             })

    assert {:ok, %{command: %{claim_token: token}}} =
             Commands.claim(c.user, c.client_id, c.environment.id, command.id, %{
               "digest" => command.digest
             })

    assert Repo.reload!(command).claim_token == token
    assert Repo.reload!(command).status == "claimed"
  end

  test "claim is single-use; identical result replay is idempotent, changed replay conflicts", c do
    command = command_fixture(c)
    claimed = claim_fixture(c, command)

    assert {:error, :command_claimed_or_settled} =
             Commands.claim(c.user, c.client_id, c.environment.id, command.id, %{
               "digest" => command.digest
             })

    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)

    assert {:ok, %{received: true}} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))

    assert {:ok, %{received: true}} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))

    assert {:error, :command_result_conflict} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, %{
               result(claimed)
               | "output" => "changed"
             })

    assert {:error, :invalid_params} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, %{
               result(claimed)
               | "output" => String.duplicate("x", 65_537)
             })
  end

  test "known result resumes the same card after deployment with frozen run selection", c do
    command = command_fixture(c)
    claimed = claim_fixture(c, command)
    assert {:ok, _} = Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))
    resumed = c.run |> Ecto.Changeset.change(resume_count: 1) |> Repo.update!()
    assert resumed.environment_id == c.environment.id
    assert resumed.project_id == c.project_id
    assert {:ok, "known result"} = Tools.call(c.run.id, 1, command.tool, %{"path" => "README.md"})
    assert {:ok, "known result"} = Tools.call(c.run.id, 1, command.tool, %{"path" => "README.md"})
    assert Repo.aggregate(Command, :count) == 1
    assert Repo.aggregate(Message, :count) == 1
    message = Repo.get!(Message, command.message_id)
    assert message.tool_output == ""
    assert Message.tool_output(message) == "known result"
    refute inspect(Repo.reload!(command)) =~ "README"
    refute inspect(message) =~ "known result"

    assert %{rows: [[encrypted_args, encrypted_result]]} =
             Repo.query!("SELECT arguments, result FROM environment_commands WHERE id = $1", [
               Ecto.UUID.dump!(command.id)
             ])

    refute encrypted_args =~ "README"
    refute encrypted_result =~ "known result"
  end

  test "claimed unknown outcomes never redispatch, including resumed reads and new terminal IDs", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    claimed = claim_fixture(c, command)
    command |> Ecto.Changeset.change(result_deadline: DateTime.add(DateTime.utc_now(), -1)) |> Repo.update!()
    Commands.sweep()
    assert {:error, reason} = Tools.call(c.run.id, 0, command.tool, %{"command" => "pwd"})
    assert reason == Commands.unknown()
    c.run |> Ecto.Changeset.change(resume_count: 1) |> Repo.update!()
    assert {:error, ^reason} = Tools.call(c.run.id, 1, command.tool, %{"command" => "pwd"})
    assert {:error, _} = Tools.call(c.run.id, 1, command.tool, %{"command" => "pwd; true"})
    assert Repo.aggregate(Command, :count) == 1

    assert {:error, :command_expired} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))

    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)
  end

  test "disabled devices and expired leases cannot claim and old results cannot cross disable", c do
    command = command_fixture(c)
    claimed = claim_fixture(c, command)
    assert {:ok, _} = Environments.disable(c.user, c.client_id, c.environment.id)

    assert {:error, :environment_disabled} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))

    assert {:error, :environment_disabled} = Commands.queued(c.user, c.client_id, c.environment.id)
  end

  test "a claimed read resumes only its existing unknown outcome, never dispatching twice", c do
    command = command_fixture(c)
    claim_fixture(c, command)
    command |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1)) |> Repo.update!()
    c.run |> Ecto.Changeset.change(resume_count: 1) |> Repo.update!()
    assert {:error, reason} = Tools.call(c.run.id, 1, command.tool, %{"path" => "README.md"})
    assert reason == Commands.unknown()
    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert Repo.aggregate(Command, :count) == 1
    assert Repo.aggregate(Message, :count) == 1
    assert Repo.reload!(command).status == "unknown"
  end

  test "another terminal command cannot bypass a queued job or an unknown claimed outcome", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    assert {:error, reason} = Tools.call(c.run.id, 0, command.tool, %{"command" => "pwd; true"})
    assert reason == Commands.unknown()
    assert Repo.aggregate(Command, :count) == 1
    command |> Ecto.Changeset.change(status: "unknown", claim_token: Ecto.UUID.generate()) |> Repo.update!()
    assert {:error, ^reason} = Tools.call(c.run.id, 0, command.tool, %{"command" => "pwd; false"})
    assert Repo.aggregate(Command, :count) == 1
  end

  test "closing a device fences unclaimed dispatch but a newer connection owns its own lease", c do
    command = command_fixture(c)
    old_connection = c.environment.connection_id
    new_connection = Ecto.UUID.generate()
    assert {:ok, _} = Environments.renew(c.user, c.client_id, c.environment.id, new_connection)
    assert :ok = Environments.close(c.environment.id, old_connection)
    assert [%{online: true}] = Environments.list(c.user).environments
    assert :ok = Environments.close(c.environment.id, new_connection)

    assert {:error, :environment_offline} =
             Commands.claim(c.user, c.client_id, c.environment.id, command.id, %{
               "digest" => command.digest
             })

    assert Repo.reload!(command).status == "queued"
  end

  test "thread archive and run cancellation fence pending claims and results", c do
    command = command_fixture(c)
    claimed = claim_fixture(c, command)
    assert {:ok, _} = Orbit.cancel_run(c.user, c.thread, c.run.id)

    assert {:error, :command_cancelled} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))

    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert {:ok, _} = Orbit.set_status(c.user, c.thread, "archived")

    assert {:error, :command_cancelled} =
             Commands.claim(c.user, c.client_id, c.environment.id, command.id, %{
               "digest" => command.digest
             })
  end

  test "dispatch permanently blocks promotion, not selection alone", c do
    newcomer = user_fixture()
    command_fixture(c)
    assert {:error, :personal_environment_history} = Orbit.add_participant(c.user, c.thread, newcomer.id)

    assert {:error, :personal_environment_history} =
             Orbit.post_message(c.user, c.thread, %{
               "body" => "share",
               "client_id" => Ecto.UUID.generate(),
               "mention_ids" => [newcomer.id]
             })

    Repo.delete!(c.run)
    {:ok, untainted, :created} = Orbit.create_private(c.user, %{"request_id" => Ecto.UUID.generate()})

    {:ok, untainted} =
      Environments.select(c.user, untainted.id, %{"environment_id" => c.environment.id, "project_id" => c.project_id})

    assert {:ok, _, :created} =
             Orbit.post_message(c.user, untainted, %{
               "body" => "share",
               "client_id" => Ecto.UUID.generate(),
               "mention_ids" => [newcomer.id],
               "address_agent" => false
             })

    assert %{kind: "shared", environment_id: nil, project_id: nil} = Repo.reload!(untainted)
  end

  test "stored results still recheck scope and attempt fences before use", c do
    command = command_fixture(c)
    claimed = claim_fixture(c, command)
    Commands.complete(c.user, c.client_id, c.environment.id, command.id, result(claimed))
    assert {:error, :stale} = Commands.outcome(c.run.id, 1, command.id)
    c.thread |> Ecto.Changeset.change(required_scopes: ["finance:read"]) |> Repo.update!()
    assert {:error, :command_cancelled} = Commands.outcome(c.run.id, 0, command.id)
  end

  defp result(claimed), do: %{"claim_token" => claimed.claim_token, "success" => true, "output" => "known result"}
end
