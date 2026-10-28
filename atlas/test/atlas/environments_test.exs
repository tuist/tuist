defmodule Atlas.EnvironmentsTest do
  use Atlas.DataCase, async: true

  import Atlas.EnvironmentFixtures
  import Atlas.OrbitFixtures

  alias Atlas.Environments
  alias Atlas.Environments.Environment
  alias Atlas.Orbit
  alias Atlas.Orbit.Runs
  alias Atlas.Repo

  setup do
    environment_fixture()
  end

  test "registration and reads are owner-private and client binding is immutable", c do
    other = user_fixture()
    assert Environments.list(other) == %{owner_id: other.id, environments: []}
    assert {:error, :not_found} = Environments.register(other, c.client_id, c.environment.id, registration())
    assert {:error, :not_found} = Environments.register(c.user, Ecto.UUID.generate(), c.environment.id, registration())
    assert {:ok, _} = Environments.disable(other, c.client_id, c.environment.id)
    assert Repo.reload!(c.environment).enabled
    assert [%{online: true}] = Environments.list(c.user).environments
  end

  test "strict bounded registration has no paths or caller-supplied ownership", c do
    for bad <- [
          Map.put(registration(), "owner_id", c.user.id),
          Map.put(registration(), "path", "/Users/owner"),
          Map.put(registration(), "terminal", "true"),
          Map.put(registration(), "projects", [%{"id" => c.project_id, "name" => "ok", "path" => "/tmp"}]),
          Map.put(registration(), "name", String.duplicate("x", 101)),
          Map.put(registration(), "name", "/Users/me"),
          Map.put(
            registration(),
            "projects",
            Enum.map(1..101, fn _ -> %{"id" => Ecto.UUID.generate(), "name" => "p"} end)
          )
        ] do
      assert {:error, :invalid_params} = Environments.register(c.user, c.client_id, Ecto.UUID.generate(), bad)
    end
  end

  test "enforces the environment ceiling including disabled registrations", c do
    for _ <- 1..31 do
      assert {:ok, _} =
               Environments.register(c.user, c.client_id, Ecto.UUID.generate(), %{registration() | "enabled" => false})
    end

    assert {:error, :environment_limit} =
             Environments.register(c.user, c.client_id, Ecto.UUID.generate(), registration())
  end

  test "project UUIDs are canonical and duplicate UUID spellings are rejected", c do
    project = %{"id" => String.upcase(c.project_id), "name" => "Project"}
    params = %{registration(c.project_id) | "projects" => [project]}
    assert {:ok, environment} = Environments.register(c.user, c.client_id, c.environment.id, params)
    assert [%{"id" => id}] = environment.projects
    assert id == c.project_id

    assert {:error, :invalid_params} =
             Environments.register(c.user, c.client_id, c.environment.id, %{
               params
               | "projects" => [project, %{project | "id" => c.project_id}]
             })
  end

  test "disable is idempotent and old online leases cannot resurrect it even after re-enable", c do
    assert {:ok, %{disabled: true}} = Environments.disable(c.user, c.client_id, c.environment.id)
    assert {:ok, %{disabled: true}} = Environments.disable(c.user, c.client_id, c.environment.id)

    assert {:error, :environment_disabled} =
             Environments.renew(c.user, c.client_id, c.environment.id, Ecto.UUID.generate(), c.environment.version)

    assert {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, registration(c.project_id))

    assert {:error, :environment_disabled} =
             Environments.renew(c.user, c.client_id, c.environment.id, Ecto.UUID.generate(), c.environment.version)

    refute Environments.online?(Repo.get!(Environment, c.environment.id))
  end

  test "selection is owner-private, rejects unknown projects and cannot change an active run", c do
    assert {:error, :not_found} =
             Environments.select(user_fixture(), c.thread.id, %{"environment_id" => nil, "project_id" => nil})

    assert {:error, :not_found} =
             Environments.select(c.user, Ecto.UUID.generate(), %{"environment_id" => nil, "project_id" => nil})

    assert {:error, :environment_run_active} =
             Environments.select(c.user, c.thread.id, %{"environment_id" => nil, "project_id" => nil})

    Repo.delete!(c.run)

    assert {:error, :environment_project_unavailable} =
             Environments.select(c.user, c.thread.id, %{
               "environment_id" => c.environment.id,
               "project_id" => Ecto.UUID.generate()
             })

    assert {:ok, thread} = Environments.select(c.user, c.thread.id, %{"environment_id" => nil, "project_id" => nil})
    assert is_nil(thread.environment_id)
    {:ok, shared} = Orbit.create_shared(c.user, %{"title" => "Shared"})

    assert {:error, :private_environment_required} =
             Environments.select(c.user, shared.id, %{
               "environment_id" => c.environment.id,
               "project_id" => c.project_id
             })
  end

  test "run creation and durable checkpoint preserve selection instead of retargeting to the thread", c do
    Repo.delete!(c.run)
    {:ok, run} = Repo.transaction(fn -> Orbit.start_run!(c.thread, 0, c.user, c.user) end)
    assert run.environment_id == c.environment.id
    assert run.project_id == c.project_id
    run |> Ecto.Changeset.change(status: "running") |> Repo.update!()
    assert :requeued = Runs.checkpoint(run.id, 0)
    c.thread |> Ecto.Changeset.change(environment_id: nil, environment_name: nil, project_id: nil) |> Repo.update!()

    resumed = Repo.reload!(run)
    assert resumed.status == "queued"
    assert resumed.resume_count == 1
    assert resumed.environment_id == c.environment.id
    assert resumed.project_id == c.project_id
    assert is_nil(Repo.reload!(c.thread).environment_id)
  end
end
