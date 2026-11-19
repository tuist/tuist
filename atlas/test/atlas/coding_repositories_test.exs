defmodule Atlas.CodingRepositoriesTest do
  use Atlas.DataCase, async: true
  use Mimic

  import Atlas.OrbitFixtures

  alias Atlas.CodingRepositories
  alias Atlas.Connections
  alias Atlas.Environments
  alias Atlas.Environments.Environment
  alias Atlas.Environments.Provider
  alias Atlas.Environments.Tuist
  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Orbit
  alias Atlas.Orbit.Run

  setup do
    user = user_fixture()
    stub(Connections, :access_token, fn caller, "github" -> {:ok, "grant-#{caller.id}"} end)
    stub(GitHubAPI, :accessible_installations, fn _ -> {:ok, [%{id: "42", name: "Acme"}]} end)

    stub(GitHubAPI, :accessible_repositories, fn _, "42" ->
      {:ok, [%{full_name: "acme/monorepo"}, %{full_name: "acme/mobile"}]}
    end)

    %{user: user}
  end

  test "personal defaults affect only new conversations, not creation retries or other people", %{user: user} do
    params = %{"installation_id" => "42", "default_repository" => "ACME/Monorepo"}
    assert {:ok, %{"default_repository" => "acme/monorepo"}} = CodingRepositories.update(user, params)
    request = %{"request_id" => Ecto.UUID.generate()}
    assert {:ok, first, :created} = Orbit.create_private(user, request)
    assert first.repository == "acme/monorepo"
    assert is_nil(first.environment_id) and is_nil(first.project_id)

    assert {:ok, _} = CodingRepositories.update(user, %{params | "default_repository" => "acme/mobile"})
    assert {:ok, replay, :existing} = Orbit.create_private(user, request)
    assert replay.repository == "acme/monorepo"
    assert {:ok, next, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
    assert next.repository == "acme/mobile"
    assert CodingRepositories.settings(user_fixture())["installation_id"] == nil

    # Return to the original value using the same (stale) authenticated user struct.
    assert {:ok, _} = CodingRepositories.update(user, params)
    assert CodingRepositories.settings(user)["default_repository"] == "acme/monorepo"
    assert {:ok, _} = CodingRepositories.update(user, %{"installation_id" => nil, "default_repository" => nil})
    assert CodingRepositories.settings(user)["default_repository"] == nil
  end

  test "revalidates source and repository visibility, preserving settings on failure", %{user: user} do
    params = %{"installation_id" => "42", "default_repository" => "acme/monorepo"}
    assert {:ok, _} = CodingRepositories.update(user, params)
    assert {:error, :installation_unavailable} = CodingRepositories.catalog(user, "99")

    assert {:error, :repository_unavailable} =
             CodingRepositories.update(user, %{params | "default_repository" => "other/private"})

    assert {:error, :invalid_params} = CodingRepositories.update(user, Map.put(params, "owner_id", user.id))
    assert {:error, :invalid_params} = CodingRepositories.update(user, %{params | "installation_id" => nil})
    stub(GitHubAPI, :accessible_repositories, fn _, _ -> {:ok, []} end)
    assert {:error, :repository_unavailable} = CodingRepositories.authorize_repository(user, "acme/monorepo")
    stub(Connections, :access_token, fn _, _ -> {:error, :not_connected} end)
    assert {:error, :github_connection_required} = CodingRepositories.catalog(user)
    assert CodingRepositories.settings(user) == params
    assert {:ok, _} = CodingRepositories.update(user, %{"installation_id" => nil, "default_repository" => nil})
  end

  test "repository selection clears execution and explicit checkouts must match, without machine fallback" do
    c = Atlas.EnvironmentFixtures.environment_fixture()
    Repo.delete!(c.run)
    assert {:ok, _} = CodingRepositories.update(c.user, %{"installation_id" => "42", "default_repository" => nil})
    selection = %{"environment_id" => nil, "project_id" => nil, "repository" => "acme/monorepo"}
    assert {:ok, thread} = Environments.select(c.user, c.thread.id, selection)
    assert thread.repository == "acme/monorepo" and is_nil(thread.environment_id)
    bound = %{selection | "environment_id" => c.environment.id, "project_id" => c.project_id}
    assert {:error, :environment_repository_mismatch} = Environments.select(c.user, c.thread.id, bound)

    registration = %{
      Atlas.EnvironmentFixtures.registration(c.project_id)
      | "projects" => [%{"id" => c.project_id, "name" => "Monorepo", "coding" => true, "repository" => "Acme/Monorepo"}]
    }

    assert {:ok, env} = Environments.register(c.user, c.client_id, c.environment.id, registration)
    refute Environments.online?(env)
    assert {:ok, thread} = Environments.select(c.user, c.thread.id, bound)
    assert thread.environment_id == c.environment.id
    assert {:error, :not_found} = Environments.select(user_fixture(), c.thread.id, selection)
    assert {:ok, shared} = Orbit.create_shared(c.user, %{"title" => "Team", "participant_ids" => []})
    assert {:error, :private_environment_required} = Environments.select(c.user, shared.id, selection)
    {:ok, _} = Orbit.set_status(c.user, thread, "archived")
    assert {:error, :archived} = Environments.select(c.user, thread.id, selection)
    assert {:ok, _} = Orbit.set_status(c.user, thread, "active")

    Repo.insert!(%Run{
      thread_id: thread.id,
      acting_user_id: c.user.id,
      initiator_id: c.user.id,
      status: "running",
      trigger_seq: 0
    })

    assert {:error, :environment_run_active} = Environments.select(c.user, thread.id, selection)
  end

  test "repository checkout selection preserves hosted lifecycle and rejects mismatches before pausing" do
    c = Atlas.EnvironmentFixtures.environment_fixture()
    Repo.delete!(c.run)
    stub(Provider, :configurations, fn -> %{"tuist" => %{module: Tuist, name: "Tuist"}} end)
    assert {:ok, _} = CodingRepositories.update(c.user, %{"installation_id" => "42", "default_repository" => nil})

    registration = %{
      Atlas.EnvironmentFixtures.registration(c.project_id)
      | "projects" => [%{"id" => c.project_id, "name" => "Code", "coding" => true, "repository" => "acme/monorepo"}]
    }

    assert {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, registration)
    bound = %{"environment_id" => c.environment.id, "project_id" => c.project_id, "repository" => "acme/monorepo"}
    assert {:ok, _} = Environments.select(c.user, c.thread.id, bound)
    assert {:ok, hosted} = Environments.select(c.user, c.thread.id, %{"provider" => "tuist"})
    assert is_nil(hosted.repository)
    environment = Repo.get!(Environment, hosted.environment_id)
    assert environment.enabled and environment.provider_state == "starting"

    assert {:error, :invalid_params} =
             Environments.select(c.user, c.thread.id, %{"provider" => "tuist", "repository" => "acme/monorepo"})

    assert {:error, :environment_repository_mismatch} =
             Environments.select(c.user, c.thread.id, %{bound | "repository" => "acme/mobile"})

    assert Repo.reload!(environment).enabled
    assert Repo.reload!(hosted).environment_id == environment.id
    assert {:ok, native} = Environments.select(c.user, c.thread.id, bound)
    assert native.environment_id == c.environment.id and native.repository == "acme/monorepo"
    stopped = Repo.reload!(environment)
    refute stopped.enabled
    assert stopped.provider_state == "stopping"
    assert stopped.version > environment.version
  end
end
