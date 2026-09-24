defmodule TuistWeb.API.MixControllerIntegrationTest do
  # End-to-end: drives TuistEx.Analytics.CompileReporter with synthetic
  # Mix compiler diagnostics, has it POST through the real /mix/builds
  # controller (no Tuist.Mix mock), and asserts that ClickHouse ends up
  # with the build row and one diagnostic per captured issue.
  use TuistTestSupport.Cases.ConnCase, async: false

  import Ecto.Query
  import Phoenix.ConnTest

  alias Tuist.ClickHouseRepo
  alias Tuist.Mix.Build
  alias Tuist.Mix.Diagnostic
  alias TuistEx.Analytics.CompileReporter
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  @endpoint TuistWeb.Endpoint

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    conn =
      conn
      |> Authentication.put_current_user(user)
      |> put_req_header("content-type", "application/json")

    on_exit(fn ->
      case Process.whereis(CompileReporter) do
        pid when is_pid(pid) ->
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end

        _ ->
          :ok
      end
    end)

    %{conn: conn, user: user, project: project}
  end

  defp submit_via_controller(conn, account, project) do
    fn payload, _opts ->
      response = post(conn, "/api/projects/#{account}/#{project}/mix/builds", payload)

      case response.status do
        status when status in 200..299 -> :ok
        status -> {:error, {:http, status, response.resp_body}}
      end
    end
  end

  test "posts a compile run and lands the build + one diagnostic row in ClickHouse", %{
    conn: conn,
    user: user,
    project: project
  } do
    submit = submit_via_controller(conn, user.account.name, project.name)
    parent = self()

    shell = fn message ->
      send(parent, {:shell, message})
      :ok
    end

    {:ok, _pid} = CompileReporter.start_link(submit: submit, shell: shell)

    CompileReporter.record(
      :elixir,
      {:ok,
       [
         %{
           severity: :warning,
           file: "lib/greeter.ex",
           source: Greeter,
           message: "unused variable name",
           position: {12, 5}
         },
         %{
           severity: :error,
           file: "lib/greeter.ex",
           source: Greeter,
           message: "undefined function greet/1",
           position: 20
         }
       ]}
    )

    :ok = CompileReporter.finish()

    refute_receive {:shell, _}, 500

    builds =
      ClickHouseRepo.all(
        from(b in Build,
          where: b.project_id == ^project.id
        )
      )

    assert [build] = builds
    assert build.status == "failure"
    assert build.diagnostics_error_count == 1
    assert build.diagnostics_warning_count == 1
    assert is_binary(build.elixir_version)
    assert build.elixir_version != ""

    diagnostics =
      ClickHouseRepo.all(
        from(d in Diagnostic,
          where: d.build_id == ^build.id,
          order_by: [asc: d.severity]
        )
      )

    assert length(diagnostics) == 2

    warning = Enum.find(diagnostics, &(&1.severity == "warning"))
    error = Enum.find(diagnostics, &(&1.severity == "error"))

    assert warning.file == "lib/greeter.ex"
    assert warning.module == "Greeter"
    assert warning.message == "unused variable name"
    assert warning.line == 12
    assert warning.column == 5
    assert warning.compiler == "elixir"

    assert error.file == "lib/greeter.ex"
    assert error.message == "undefined function greet/1"
    assert error.line == 20
  end
end
