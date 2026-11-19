defmodule Atlas.EnvironmentFixtures do
  @moduledoc false

  alias Atlas.Environments
  alias Atlas.Environments.Commands
  alias Atlas.Orbit
  alias Atlas.Orbit.Rendering
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Repo

  def registration(project_id \\ Ecto.UUID.generate()) do
    %{
      "name" => "Personal Mac",
      "enabled" => true,
      "terminal" => true,
      "display" => false,
      "projects" => [%{"id" => project_id, "name" => "Project"}]
    }
  end

  def environment_fixture do
    user = Atlas.OrbitFixtures.user_fixture()
    {client_id, token} = Atlas.PushFixtures.native_access_token(user)
    id = Ecto.UUID.generate()
    project_id = Ecto.UUID.generate()
    {:ok, _environment} = Environments.register(user, client_id, id, registration(project_id))
    {:ok, environment} = Environments.renew(user, client_id, id, Ecto.UUID.generate())
    {:ok, thread, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
    {:ok, thread} = Environments.select(user, thread.id, %{"environment_id" => id, "project_id" => project_id})

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        acting_user_id: user.id,
        initiator_id: user.id,
        environment_id: id,
        project_id: project_id,
        status: "running",
        trigger_seq: 0
      })

    %{
      user: user,
      client_id: client_id,
      token: token,
      environment: environment,
      project_id: project_id,
      thread: thread,
      run: run
    }
  end

  def command_fixture(context, tool \\ "environment_read_file", args \\ %{"path" => "README.md"}) do
    {:ok, command} =
      Runs.with_attempt(context.run.id, context.run.resume_count, fn thread, run ->
        key =
          :crypto.hash(:sha256, :erlang.term_to_binary({tool, args}, [:deterministic])) |> Base.encode16(case: :lower)

        message =
          Orbit.append!(thread, %{
            kind: "tool",
            run_id: run.id,
            tool_name: tool,
            tool_status: "running",
            tool_call_key: key,
            device_input: Rendering.input(args)
          })

        Commands.reserve!(thread, run, message, args)
      end)

    command
  end

  def claim_fixture(context, command) do
    {:ok, %{command: claimed}} =
      Commands.claim(context.user, context.client_id, context.environment.id, command.id, %{
        "digest" => command.digest
      })

    claimed
  end
end
