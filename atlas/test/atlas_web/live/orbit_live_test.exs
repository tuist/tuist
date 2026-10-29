defmodule AtlasWeb.OrbitLiveTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.EnvironmentFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Environments
  alias Atlas.Environments.Command
  alias Atlas.Environments.Commands
  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Orbit

  test "sending uses the chosen project and does not log prompt bodies", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {client, _token} = Atlas.PushFixtures.native_access_token(user)
    environment = Ecto.UUID.generate()
    project = Ecto.UUID.generate()
    params = %{registration(project) | "projects" => [%{"id" => project, "name" => "Code", "coding" => true}]}
    {:ok, _} = Environments.register(user, client, environment, params)
    {:ok, thread, _} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
    {:ok, view, _} = live(conn, ~p"/orbit/#{thread.id}")
    view |> form("#orbit-project-form", selection: %{project: "#{environment}:#{project}"}) |> render_change()
    render_async(view)
    assert {:ok, %{project_id: ^project}} = Orbit.fetch(user, thread.id)
    view |> form("#orbit-project-form", selection: %{project: "_server"}) |> render_change()
    render_async(view)
    assert {:ok, %{environment_id: nil, project_id: nil}} = Orbit.fetch(user, thread.id)
    view |> form("#orbit-project-form", selection: %{project: "#{environment}:#{project}"}) |> render_change()
    render_async(view)
    body = "Private coding prompt #{System.unique_integer([:positive])}"

    logs =
      ExUnit.CaptureLog.capture_log(fn ->
        view |> form("#orbit-composer", message: %{body: body}) |> render_submit()
      end)

    refute logs =~ body
    assert has_element?(view, "#orbit-messages article[data-kind='human']", body)
    refute has_element?(view, "#orbit-body", body)
    assert {:ok, %{title: ^body}} = Orbit.fetch(user, thread.id)
  end

  test "repository override filters checkouts, never selects one implicitly, and preserves drafts", %{conn: conn} do
    c = environment_fixture()
    Atlas.Repo.delete!(c.run)
    conn = Plug.Test.init_test_session(conn, %{"user_id" => c.user.id})
    stub(Atlas.Connections, :access_token, fn _, "github" -> {:ok, "grant"} end)
    stub(GitHubAPI, :accessible_installations, fn _ -> {:ok, [%{id: "42", name: "Acme"}]} end)

    stub(GitHubAPI, :accessible_repositories, fn _, _ ->
      {:ok, [%{full_name: "acme/code"}, %{full_name: "acme/uncloned"}]}
    end)

    {:ok, _} = Atlas.CodingRepositories.update(c.user, %{"installation_id" => "42", "default_repository" => nil})

    params = %{
      registration(c.project_id)
      | "projects" => [
          %{"id" => c.project_id, "name" => "Code", "coding" => true, "repository" => "acme/code"},
          %{"id" => Ecto.UUID.generate(), "name" => "Unrelated", "coding" => true, "repository" => "other/repo"}
        ]
    }

    {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, params)
    {:ok, view, _} = live(conn, ~p"/orbit/#{c.thread.id}")
    render_async(view)
    view |> form("#orbit-composer", message: %{body: "Keep my draft"}) |> render_change()
    view |> form("#orbit-repository-form", repository: %{repository: "acme/code"}) |> render_change()
    render_async(view)
    assert {:ok, %{repository: "acme/code", environment_id: nil}} = Orbit.fetch(c.user, c.thread.id)
    assert has_element?(view, "#orbit-project option", "Code")
    refute has_element?(view, "#orbit-project option", "Unrelated")
    assert has_element?(view, "#orbit-body", "Keep my draft")
    view |> form("#orbit-repository-form", repository: %{repository: "acme/uncloned"}) |> render_change()
    render_async(view)
    assert has_element?(view, "#orbit-repository-unavailable")
    assert {:ok, %{repository: "acme/uncloned", environment_id: nil}} = Orbit.fetch(c.user, c.thread.id)
    assert has_element?(view, "#orbit-body", "Keep my draft")
  end

  test "requires sign-in and never renders another owner's private history", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/orbit")
    c = environment_fixture()
    {conn, _other} = log_in_user(conn)
    {:ok, view, _} = live(conn, ~p"/orbit/#{c.thread.id}")
    assert has_element?(view, "#orbit-welcome")
    refute has_element?(view, "#orbit-composer")
    refute has_element?(view, "#orbit-jobs")
    refute has_element?(view, "#orbit-project")
  end

  test "creates distinct private threads and preserves per-thread drafts across selection and reconciliation", %{
    conn: conn
  } do
    {conn, user} = log_in_user(conn)
    {:ok, view, _} = live(conn, ~p"/orbit")
    view |> element("#orbit-new") |> render_click()
    path = assert_patch(view)
    id = List.last(String.split(path, "/"))
    assert {:ok, first} = Orbit.fetch(user, id)
    assert first.kind == "private"
    view |> form("#orbit-composer", message: %{body: "Keep my unsent change"}) |> render_change()
    send(view.pid, :reconcile)
    assert has_element?(view, "#orbit-body", "Keep my unsent change")

    view |> element("#orbit-new") |> render_click()
    second_path = assert_patch(view)
    refute second_path == path
    view |> form("#orbit-composer", message: %{body: "Second draft"}) |> render_change()
    render_patch(view, path)
    assert has_element?(view, "#orbit-body", "Keep my unsent change")
    render_patch(view, second_path)
    assert has_element?(view, "#orbit-body", "Second draft")
  end

  test "projects are owner-scoped and queued command cancellation preserves the composer draft", %{conn: conn} do
    c = environment_fixture()
    conn = Plug.Test.init_test_session(conn, %{"user_id" => c.user.id})
    params = %{registration(c.project_id) | "projects" => [%{"id" => c.project_id, "name" => "Code", "coding" => true}]}
    {:ok, _} = Environments.register(c.user, c.client_id, c.environment.id, params)
    {:ok, _} = Environments.renew(c.user, c.client_id, c.environment.id, Ecto.UUID.generate())
    job = command_fixture(c, "bash", %{"command" => "printf verified"})
    {:ok, view, _} = live(conn, ~p"/orbit/#{c.thread.id}")
    assert has_element?(view, "#orbit-project option", "isolated coding")
    assert has_element?(view, "#job-#{job.id}")
    refute has_element?(view, "[data-part='conversation-header'] button", "Stop Pip")
    refute has_element?(view, "[data-part='conversation-footer'] #job-#{job.id}")
    assert has_element?(view, "#job-#{job.id} [role='status']", "Queued")
    view |> form("#orbit-composer", message: %{body: "Keep this draft"}) |> render_change()
    view |> element("#job-#{job.id} button") |> render_click()
    assert {:ok, %{commands: [%{status: "cancelled"}]}} = Commands.list(c.user, c.thread.id)
    assert has_element?(view, "#orbit-body", "Keep this draft")
    refute has_element?(view, "#job-#{job.id} button")
    view |> element("#orbit-stop") |> render_click()
    assert has_element?(view, "#orbit-activity", "Cancellation requested")
    assert has_element?(view, "#orbit-stop[disabled]")
    assert has_element?(view, "#orbit-body", "Keep this draft")
  end

  test "command progress and cancellation update inline without a new history message", %{conn: conn} do
    c = environment_fixture()
    conn = Plug.Test.init_test_session(conn, %{"user_id" => c.user.id})
    job = command_fixture(c, "environment_terminal", %{"command" => "printf progress"})
    claim_fixture(c, job)
    {:ok, view, _} = live(conn, ~p"/orbit/#{c.thread.id}")
    assert has_element?(view, "#job-#{job.id} [role='status']", "Running")

    Atlas.Repo.get!(Command, job.id)
    |> Ecto.Changeset.change(progress_output: "Unique progress evidence", progress_sequence: 1)
    |> Atlas.Repo.update!()

    send(view.pid, :reconcile)
    assert has_element?(view, "#job-#{job.id} pre", "Unique progress evidence")
    view |> element("#job-#{job.id} button[aria-label='Cancel command']") |> render_click()
    assert has_element?(view, "#job-#{job.id} [role='status']", "Cancellation requested")
    assert has_element?(view, "#job-#{job.id} button[disabled]")

    Atlas.Repo.transaction(fn ->
      for index <- 1..51, do: Orbit.append!(c.thread, %{kind: "system", body: "Later message #{index}"})
    end)

    send(view.pid, :reconcile)
    assert has_element?(view, "#job-#{job.id} [role='status']", "Cancellation requested")
    refute has_element?(view, "#orbit-messages #job-#{job.id}")
    view |> element("#orbit-older-messages") |> render_click()
    assert has_element?(view, "#orbit-messages #job-#{job.id}")
    refute has_element?(view, "[data-part='assistant-activity'] #job-#{job.id}")
  end

  test "shared and archived conversations do not show private execution or response controls", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, thread} = Orbit.create_shared(user, %{"title" => "Team discussion", "participant_ids" => []})
    {:ok, view, _} = live(conn, ~p"/orbit/#{thread.id}")
    assert has_element?(view, "#orbit-composer")
    refute has_element?(view, "#orbit-project")
    refute has_element?(view, "#orbit-activity")
    {:ok, _} = Orbit.set_status(user, thread, "archived")
    send(view.pid, :reconcile)
    refute has_element?(view, "#orbit-composer")
    refute has_element?(view, "#orbit-stop")
    assert has_element?(view, "[data-part='archived-note']")
  end
end
