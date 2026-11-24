defmodule TuistWeb.Plugs.PulseRoutesPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "old ~ paths redirect permanently to the same page", %{conn: conn} do
    conn = get(conn, "/acme/~/pulse/errors/issues/a%2Fb%20c/events/1?range=24h&service=server")
    assert conn.status == 301
    assert redirected_to(conn, 301) == "/acme/pulse/errors/issues/a%2Fb%20c/events/1?range=24h&service=server"

    assert conn |> recycle() |> get("/acme/~/pulse") |> redirected_to(301) == "/acme/pulse"
  end

  test "a project named pulse from before the reservation keeps its overview", %{conn: conn} do
    account = AccountsFixtures.organization_fixture().account
    project = ProjectsFixtures.project_fixture(account: account, visibility: :public)
    Repo.update_all(from(p in Project, where: p.id == ^project.id), set: [name: "pulse"])

    # Before any login check, so anonymous visitors of a public project get there too.
    assert conn |> get("/#{account.name}/pulse?ref=x") |> redirected_to(302) == "/#{account.name}/pulse/analytics?ref=x"

    # Where Pulse runs, the Pulse page wins.
    stub(Tuist.Environment, :pulse_config, fn -> [account_id: account.id] end)
    stub(Tuist.FeatureFlags, :pulse_enabled?, fn _ -> true end)
    refute conn |> recycle() |> get("/#{account.name}/pulse") |> redirected_to(302) =~ "/analytics"
  end

  test "without a pulse project, the Pulse page is left alone", %{conn: conn} do
    account = AccountsFixtures.organization_fixture().account
    refute conn |> get("/#{account.name}/pulse") |> redirected_to(302) =~ "/analytics"
  end
end
