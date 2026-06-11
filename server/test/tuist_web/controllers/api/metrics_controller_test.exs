defmodule TuistWeb.API.MetricsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  @from DateTime.to_unix(~U[2024-04-28 00:00:00Z])
  @to DateTime.to_unix(~U[2024-04-30 12:00:00Z])

  setup %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> true end)

    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    %{conn: conn, user: user, project: project}
  end

  describe "GET /api/projects/:account_handle/:project_handle/builds/metrics/duration" do
    test "returns time-bucketed build duration percentiles", %{conn: conn, user: user, project: project} do
      RunsFixtures.build_fixture(
        project_id: project.id,
        duration: 3000,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/duration?from=#{@from}&to=#{@to}")

      assert %{
               "dates" => dates,
               "average" => %{"values" => average_values, "total" => average_total},
               "p50" => %{"values" => p50_values, "total" => _p50_total},
               "p90" => %{"values" => _, "total" => _},
               "p99" => %{"values" => _, "total" => _},
               "trend" => _trend
             } = json_response(conn, 200)

      assert length(dates) == 3
      assert length(average_values) == 3
      assert length(p50_values) == 3
      assert average_total == 3000.0
    end

    test "authorizes an account token with project:builds:read across the account's projects", %{
      conn: conn,
      project: project
    } do
      RunsFixtures.build_fixture(
        project_id: project.id,
        duration: 1000,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      {:ok, account} = Tuist.Accounts.get_account_by_id(project.account_id)

      conn =
        conn
        |> Plug.Conn.assign(:current_subject, %AuthenticatedAccount{
          account: account,
          scopes: ["project:builds:read"],
          all_projects: true,
          project_ids: []
        })
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/duration?from=#{@from}&to=#{@to}")

      assert %{"average" => %{"total" => 1000.0}} = json_response(conn, 200)
    end

    test "applies the is_ci filter", %{conn: conn, user: user, project: project} do
      RunsFixtures.build_fixture(
        project_id: project.id,
        duration: 5000,
        is_ci: true,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      RunsFixtures.build_fixture(
        project_id: project.id,
        duration: 1000,
        is_ci: false,
        inserted_at: ~U[2024-04-29 03:00:00Z]
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(
          ~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/duration?from=#{@from}&to=#{@to}&is_ci=true"
        )

      assert %{"average" => %{"total" => 5000.0}} = json_response(conn, 200)
    end

    test "returns 400 when the range is invalid", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/duration?from=#{@to}&to=#{@from}")

      assert json_response(conn, 400)["message"] =~ "must be greater"
    end

    test "returns 403 when the account token cannot access the project", %{conn: conn, project: project} do
      {:ok, account} = Tuist.Accounts.get_account_by_id(project.account_id)

      conn =
        conn
        |> Plug.Conn.assign(:current_subject, %AuthenticatedAccount{
          account: account,
          scopes: ["project:builds:read"],
          all_projects: false,
          project_ids: []
        })
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/duration?from=#{@from}&to=#{@to}")

      assert json_response(conn, 403)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/metrics/duration" do
    test "returns time-bucketed test duration percentiles", %{conn: conn, user: user, project: project} do
      RunsFixtures.test_fixture(
        project_id: project.id,
        duration: 4000,
        ran_at: ~N[2024-04-29 03:00:00]
      )

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/metrics/duration?from=#{@from}&to=#{@to}")

      assert %{
               "dates" => dates,
               "average" => %{"total" => average_total},
               "p50" => %{"values" => _},
               "p90" => %{"values" => _},
               "p99" => %{"values" => _}
             } = json_response(conn, 200)

      assert length(dates) == 3
      assert average_total == 4000.0
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/builds/metrics/dimensions/:dimension/values" do
    test "returns the project's recent build schemes", %{conn: conn, user: user, project: project} do
      RunsFixtures.build_fixture(project_id: project.id, scheme: "App")

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/dimensions/scheme/values")

      assert %{"values" => values} = json_response(conn, 200)
      assert "App" in values
    end

    test "returns the project's recent build configurations", %{conn: conn, user: user, project: project} do
      RunsFixtures.build_fixture(project_id: project.id, configuration: "Debug")

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/builds/metrics/dimensions/configuration/values")

      assert %{"values" => values} = json_response(conn, 200)
      assert "Debug" in values
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/tests/metrics/dimensions/:dimension/values" do
    test "returns the project's recent test schemes", %{conn: conn, user: user, project: project} do
      RunsFixtures.test_fixture(project_id: project.id, scheme: "AppTests")

      conn =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{project.account.name}/#{project.name}/tests/metrics/dimensions/scheme/values")

      assert %{"values" => values} = json_response(conn, 200)
      assert "AppTests" in values
    end
  end
end
