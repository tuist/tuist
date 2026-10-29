defmodule TuistWeb.RunnerBitriseReportsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Repo
  alias Tuist.Runners.Bitrise
  alias Tuist.Runners.Bitrise.Build
  alias Tuist.Runners.Bitrise.ReportToken
  alias Tuist.Runners.Buildkite.ReportToken, as: BuildkiteReportToken

  setup do
    %{account: account} = organization_fixture(preload: [:account])
    {:ok, connection} = Bitrise.upsert_connection(account.id, %{workspace_slug: "n26", api_token: "secret"})

    build =
      Repo.insert!(%Build{
        account_id: account.id,
        connection_id: connection.id,
        build_slug: "build-claimed",
        app_slug: "app-ios",
        stack_identifier: "agent-pool-ios"
      })

    token = ReportToken.mint(%{workflow_job_id: build.workflow_job_id, account_id: account.id})

    %{account: account, build: build, token: token}
  end

  defp authed(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  test "binds the build the agent reports", %{conn: conn, account: account, build: build, token: token} do
    account_id = account.id
    workflow_job_id = build.workflow_job_id

    expect(Bitrise, :record_build_started, fn %{workflow_job_id: ^workflow_job_id, account_id: ^account_id},
                                              "build-taken",
                                              "app-ios" ->
      :ok
    end)

    conn =
      conn
      |> authed(token)
      |> post("/api/internal/runners/jobs/bitrise/started", %{build_slug: "build-taken", app_slug: "app-ios"})

    assert response(conn, 204)
  end

  test "rejects a build outside the connected pools", %{conn: conn, token: token} do
    stub(Bitrise, :record_build_started, fn _claimed, _slug, _app -> {:error, :invalid_build} end)

    conn = conn |> authed(token) |> post("/api/internal/runners/jobs/bitrise/started", %{build_slug: "x", app_slug: "y"})

    assert json_response(conn, 422)
  end

  test "requires both slugs", %{conn: conn, token: token} do
    reject(Bitrise, :record_build_started, 3)

    conn = conn |> authed(token) |> post("/api/internal/runners/jobs/bitrise/started", %{build_slug: "x"})

    assert json_response(conn, 400)
  end

  test "refuses another lane's report token", %{conn: conn, account: account, build: build} do
    reject(Bitrise, :record_build_started, 3)
    token = BuildkiteReportToken.mint(%{workflow_job_id: build.workflow_job_id, account_id: account.id})

    conn = conn |> authed(token) |> post("/api/internal/runners/jobs/bitrise/started", %{build_slug: "x", app_slug: "y"})

    assert json_response(conn, 401)
  end
end
