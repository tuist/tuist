defmodule AtlasWeb.NativeEnvironmentCommandsControllerTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.EnvironmentFixtures
  import Atlas.OrbitFixtures
  import Atlas.PushFixtures, only: [native_access_token: 1]
  import Ecto.Query

  alias Atlas.Environments
  alias Atlas.Environments.Command
  alias Atlas.Environments.Commands
  alias Atlas.OAuth.AccessTokens
  alias Atlas.Orbit
  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Orbit.Tools
  alias Atlas.Repo

  setup do
    c = environment_fixture()
    {_phone_client, phone_token} = native_access_token(c.user)
    Map.merge(c, %{mac: api(c.token), phone: api(phone_token)})
  end

  test "terminal opt-in immediately queues a durable job without a per-command decision", c do
    assert {:ok, ticket} = Tools.call(c.run.id, 0, "environment_terminal", %{"command" => "xcodebuild -version"})

    assert %{"command_id" => command_id, "status" => "queued"} = JSON.decode!(ticket)
    refute Map.has_key?(JSON.decode!(ticket), "approval_required")

    assert {:ok, ^ticket} = Tools.call(c.run.id, 0, "environment_terminal", %{"command" => "xcodebuild -version"})
    assert Repo.aggregate(Command, :count) == 1
    command = Repo.get!(Command, command_id)

    assert %{"commands" => [%{"id" => ^command_id, "execution_timeout_seconds" => 1_800}]} =
             get(c.mac, device(c) <> "/commands") |> json_response(200)

    assert %{"commands" => [entry]} = get(c.phone, activity(c)) |> json_response(200)

    assert Map.keys(entry) |> Enum.sort() ==
             ~w(cancel_requested command digest environment_id environment_name execution_timeout_seconds id message_id output progress_sequence project_id project_name status success)

    assert entry["command"] == "xcodebuild -version"
    assert entry["execution_timeout_seconds"] == 1_800
    assert entry["success"] == nil
    refute Map.has_key?(entry, "claim_token")
    assert get_resp_header(get(c.phone, activity(c)), "cache-control") == ["no-store"]

    claim_path = device(c) <> "/commands/#{command.id}/claim"
    assert post(c.mac, claim_path, %{"digest" => command.digest, "approved" => true}) |> json_response(422)
    assert post(c.phone, claim_path, %{"digest" => command.digest}) |> json_response(404)

    assert %{"command" => %{"claim_token" => token}} =
             post(c.mac, claim_path, %{"digest" => command.digest}) |> json_response(200)

    assert Repo.reload!(command).claim_token == token
    assert DateTime.diff(Repo.reload!(command).result_deadline, Repo.reload!(command).execution_deadline) == 300
  end

  test "cancellation denies missing/wrong digest, other owner, extra fields and non-native clients", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    path = action(c, command, "cancel")
    assert post(c.phone, path, %{}) |> json_response(422)

    assert post(c.phone, path, %{"digest" => String.duplicate("f", 64)}) |> json_response(409) == %{
             "error" => "command_digest_mismatch"
           }

    assert post(c.phone, path, %{"digest" => command.digest, "command" => "other"})
           |> json_response(422)

    assert bearer(user_fixture()) |> get(activity(c)) |> json_response(404)
    {_id, other_token} = native_access_token(user_fixture())
    assert post(api(other_token), path, %{"digest" => command.digest}) |> json_response(404)
    assert post(bearer(c.user), path, %{"digest" => command.digest}) |> json_response(403)
    {_id, revoked_token} = native_access_token(c.user)
    assert {:ok, _} = AccessTokens.revoke(AccessTokens.get_by(value: revoked_token))
    assert post(api(revoked_token), path, %{"digest" => command.digest}) |> json_response(401)
    assert Repo.reload!(command).status == "queued"
  end

  test "configuration versions, disabled devices and lost history scopes still deny dispatch", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    claim_path = device(c) <> "/commands/#{command.id}/claim"
    claim = %{"digest" => command.digest}
    c.thread |> Ecto.Changeset.change(required_scopes: ["finance:read"]) |> Repo.update!()
    assert post(c.mac, claim_path, claim) |> json_response(409) == %{"error" => "command_cancelled"}
    c.thread |> Repo.reload!() |> Ecto.Changeset.change(required_scopes: []) |> Repo.update!()

    assert {:ok, _} =
             Environments.register(c.user, c.client_id, c.environment.id, %{
               registration(c.project_id)
               | "display" => true
             })

    assert post(c.mac, claim_path, claim) |> json_response(409) == %{
             "error" => "environment_disabled"
           }

    assert {:ok, _} = Environments.disable(c.user, c.client_id, c.environment.id)
    assert post(c.mac, claim_path, claim) |> json_response(409)
    assert Repo.reload!(command).claim_token == nil
  end

  test "queued cancellation settles without dispatch or inference and permits a later command", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})

    assert post(c.phone, action(c, command, "cancel"), %{"digest" => command.digest}) |> json_response(200) == %{
             "received" => true
           }

    assert post(c.phone, action(c, command, "cancel"), %{"digest" => command.digest}) |> json_response(200)
    next = command_fixture(c, "environment_terminal", %{"command" => "true"})

    assert post(c.phone, action(c, next, "cancel"), %{"digest" => next.digest}) |> json_response(200) == %{
             "received" => true
           }

    assert Repo.reload!(next).status == "cancelled"
    assert Repo.reload!(command).status == "cancelled"
    assert get(c.mac, device(c) <> "/commands") |> json_response(200) == %{"commands" => []}
    refute Repo.exists?(from m in Message, where: m.address_agent == true)
    refute Repo.reload!(command).continuation_message_id
  end

  test "bounded monotonic encrypted progress, stale/duplicate sequences and honest claimed cancellation", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "xcodebuild"})
    claimed = claim_fixture(c, command)
    progress = device(c) <> "/commands/#{command.id}/progress"
    payload = %{"claim_token" => claimed.claim_token, "sequence" => 2, "output" => "private build tail"}
    assert post(c.mac, progress, payload) |> json_response(200) == %{"received" => true, "cancel_requested" => false}
    deadline = Repo.reload!(command).execution_deadline
    assert post(c.mac, progress, payload) |> json_response(200)
    assert post(c.mac, progress, %{payload | "sequence" => 1, "output" => "stale"}) |> json_response(200)
    assert post(c.mac, progress, %{payload | "output" => "changed"}) |> json_response(409)

    for invalid <- [
          %{payload | "sequence" => 0},
          %{payload | "sequence" => 1.1},
          %{payload | "output" => String.duplicate("é", 24_577)},
          %{payload | "claim_token" => Ecto.UUID.generate()}
        ] do
      assert post(c.mac, progress, invalid).status in [409, 422]
    end

    assert post(c.phone, progress, payload) |> json_response(404)
    assert Repo.reload!(command).progress_output == "private build tail"
    assert Repo.reload!(command).execution_deadline == deadline
    assert post(c.phone, action(c, command, "cancel"), %{"digest" => command.digest}) |> json_response(200)
    assert %{status: "claimed", cancel_requested: true} = Repo.reload!(command)
    assert post(c.mac, progress, payload) |> json_response(200) == %{"received" => true, "cancel_requested" => true}

    assert %{"commands" => [%{"status" => "claimed", "success" => nil, "cancel_requested" => true}]} =
             get(c.phone, activity(c)) |> json_response(200)

    result = %{
      "claim_token" => claimed.claim_token,
      "success" => false,
      "output" => "Actually stopped the process group."
    }

    assert post(c.mac, device(c) <> "/commands/#{command.id}/result", result) |> json_response(200)
    assert %{status: "settled", cancel_requested: true} = Repo.reload!(command)
    notice = Repo.get!(Message, Repo.reload!(command).continuation_message_id)
    refute notice.address_agent
    refute notice.body =~ "process group"
    assert notice.device_output =~ "Actually stopped"

    assert %{rows: [[encrypted]]} =
             Repo.query!("SELECT progress_output FROM environment_commands WHERE id = $1", [Ecto.UUID.dump!(command.id)])

    refute encrypted =~ "private build tail"
  end

  test "fixed admission expiry, execution deadline and delivery grace never redispatch or auto-resume unknown", c do
    pending = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    pending |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1)) |> Repo.update!()

    assert post(c.mac, device(c) <> "/commands/#{pending.id}/claim", %{"digest" => pending.digest})
           |> json_response(409) == %{"error" => "command_expired"}

    Commands.sweep()
    assert Repo.reload!(pending).status == "expired"
    command = command_fixture(c, "environment_terminal", %{"command" => "true"})
    claimed = claim_fixture(c, command)

    command
    |> Ecto.Changeset.change(
      execution_deadline: DateTime.add(DateTime.utc_now(), -1),
      expires_at: DateTime.add(DateTime.utc_now(), -600)
    )
    |> Repo.update!()

    assert {:ok, _} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, %{
               "claim_token" => claimed.claim_token,
               "success" => true,
               "output" => "within delivery grace"
             })

    next = command_fixture(c, "environment_terminal", %{"command" => "false"})
    claim_fixture(c, next)
    next |> Ecto.Changeset.change(result_deadline: DateTime.add(DateTime.utc_now(), -1)) |> Repo.update!()
    Commands.sweep()
    assert Repo.reload!(next).status == "unknown"
    refute Repo.reload!(next).continuation_message_id
    assert {:error, _} = Tools.call(c.run.id, 0, "environment_terminal", %{"command" => "different"})
    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)
  end

  test "archive permanently fences terminal jobs, even after restore", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    claim_fixture(c, command)
    assert :ok = Runs.complete(c.run.id, 0, {:ok, "Command queued"})
    assert {:ok, _} = Orbit.set_status(c.user, c.thread, "archived")
    assert {:ok, _} = Orbit.set_status(c.user, c.thread, "active")
    assert %{status: "unknown", cancel_requested: true} = Repo.reload!(command)
    assert {:ok, []} = Commands.queued(c.user, c.client_id, c.environment.id)
    assert Repo.aggregate(Run, :count) == 1
  end

  test "cancelled source runs fence late terminal results without inference", c do
    command = command_fixture(c, "environment_terminal", %{"command" => "pwd"})
    claimed = claim_fixture(c, command)
    assert {:ok, _} = Orbit.cancel_run(c.user, c.thread, c.run.id)

    assert {:error, :command_cancelled} =
             Commands.complete(c.user, c.client_id, c.environment.id, command.id, %{
               "claim_token" => claimed.claim_token,
               "success" => true,
               "output" => "late result"
             })

    assert :ok = Runs.complete(c.run.id, 0, {:ok, "Cancelled run must not succeed."})
    assert Repo.reload!(c.run).status == "cancelled"
    assert %{status: "unknown", cancel_requested: true, continuation_message_id: nil} = Repo.reload!(command)
    refute Repo.exists?(from m in Message, where: m.address_agent == true)
  end

  test "activity is terminal-only, active first, bounded to 32 rows and a total UTF-8 output budget", c do
    for index <- 1..35 do
      command = command_fixture(c, "environment_terminal", %{"command" => "echo #{index}"})

      command
      |> Ecto.Changeset.change(
        status: "settled",
        claim_token: Ecto.UUID.generate(),
        result: JSON.encode!(%{success: false, output: String.duplicate("界", 21_845)})
      )
      |> Repo.update!()
    end

    active = command_fixture(c, "environment_terminal", %{"command" => "pending"})
    command_fixture(c)
    response = get(c.phone, activity(c))
    assert %{"commands" => [first | _] = entries} = json_response(response, 200)
    assert length(entries) == 32
    assert first["id"] == active.id
    assert Enum.all?(entries, &(String.valid?(&1["output"]) and byte_size(&1["output"]) <= 49_152))
    assert Enum.sum(Enum.map(entries, &byte_size(&1["output"]))) <= 262_144
    assert byte_size(response.resp_body) < 1_048_576

    # Valid UTF-8 control characters can cost six bytes each once JSON-escaped.
    # Even adversarial command/output text must fit the unchanged native reader.
    escaped_command = String.duplicate(<<1>>, 8_000)

    Repo.all(from command in Command, where: command.tool == "environment_terminal" and command.status == "settled")
    |> Enum.each(fn command ->
      arguments = command.arguments |> JSON.decode!() |> Map.put("command", escaped_command)

      command
      |> Ecto.Changeset.change(
        arguments: JSON.encode!(arguments),
        result: JSON.encode!(%{success: false, output: String.duplicate(<<1>>, 65_536)})
      )
      |> Repo.update!()
    end)

    response = get(c.phone, activity(c))
    assert %{"commands" => [first | settled]} = json_response(response, 200)
    assert first["id"] == active.id
    assert length(settled) in 1..31
    assert Enum.all?(settled, &(&1["command"] == escaped_command))
    assert byte_size(response.resp_body) < 1_048_576
  end

  defp api(token), do: build_conn() |> put_req_header("authorization", "Bearer #{token}")
  defp activity(c), do: "/api/native/orbit/threads/#{c.thread.id}/environment-commands"
  defp action(c, command, name), do: activity(c) <> "/#{command.id}/#{name}"
  defp device(c), do: "/api/me/environments/#{c.environment.id}"
end
