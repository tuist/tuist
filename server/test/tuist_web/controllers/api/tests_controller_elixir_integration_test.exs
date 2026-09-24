defmodule TuistWeb.API.TestsControllerElixirIntegrationTest do
  # End-to-end: drives the tuist_ex ExUnit formatter with synthetic
  # ExUnit.Test lifecycle events, has it POST into the real /tests
  # controller (no Mimic on Tuist.Tests), and asserts that ClickHouse
  # ends up with granular test_case_run rows.
  use TuistTestSupport.Cases.ConnCase, async: false

  import Ecto.Query
  import Phoenix.ConnTest

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunByTestRun
  alias TuistEx.Analytics.ExUnitFormatter
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

    %{conn: conn, user: user, project: project}
  end

  defp new_test(overrides) do
    struct(
      ExUnit.Test,
      Keyword.merge(
        [
          name: :"test example",
          module: SomeModuleTest,
          state: nil,
          time: 1_000,
          tags: %{describe: nil, file: "test/some_test.exs", line: 1}
        ],
        overrides
      )
    )
  end

  defp submit_via_controller(conn, account, project) do
    fn payload, _opts ->
      response = post(conn, "/api/projects/#{account}/#{project}/tests", payload)

      case response.status do
        status when status in 200..299 -> :ok
        status -> {:error, {:http, status, response.resp_body}}
      end
    end
  end

  test "posts an ExUnit run and lands test_case_run rows in ClickHouse with per-case granularity",
       %{
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

    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: submit, shell: shell)

    stacktrace = [
      {GreeterTest, :"test stumbles", 1, [file: ~c"test/greeter_test.exs", line: 42]}
    ]

    events = [
      {:suite_started, [max_cases: 8]},
      {:test_finished,
       new_test(
         name: :"test greets the world",
         module: GreeterTest,
         time: 4_200,
         tags: %{describe: "greetings", file: "test/greeter_test.exs", line: 3}
       )},
      {:test_finished,
       new_test(
         name: :"test greets the world in Portuguese",
         module: GreeterTest,
         time: 500,
         tags: %{describe: "greetings", file: "test/greeter_test.exs", line: 15}
       )},
      {:test_finished,
       new_test(
         name: :"test stumbles",
         module: GreeterTest,
         state:
           {:failed,
            [{:error, %RuntimeError{message: "boom in greeter"}, stacktrace}]},
         time: 3_000,
         tags: %{describe: nil, file: "test/greeter_test.exs", line: 40}
       )},
      {:test_finished,
       new_test(
         name: :"test skipped for now",
         module: GreeterTest,
         state: {:skipped, "not ready"},
         time: 0,
         tags: %{describe: nil, file: "test/greeter_test.exs", line: 60}
       )},
      {:suite_finished, %{run: 8_000, load: 200}}
    ]

    Enum.each(events, &GenServer.cast(pid, &1))

    refute_receive {:shell, _}, 500

    :ok = GenServer.stop(pid)

    # Query ClickHouse for the test_case_runs written by the run. The exact
    # test_run_id is opaque here (the formatter generated it), so we look up
    # by module_name — no other module runs are seeded in this test.
    test_case_runs =
      ClickHouseRepo.all(
        from(r in TestCaseRun,
          where: r.module_name == ^"GreeterTest",
          order_by: [asc: r.name]
        )
      )

    names =
      test_case_runs
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert names == [
             "test greets the world",
             "test greets the world in Portuguese",
             "test skipped for now",
             "test stumbles"
           ]

    by_name = Map.new(test_case_runs, &{&1.name, &1})

    assert by_name["test greets the world"].status == "success"
    assert by_name["test greets the world"].suite_name == "greetings"
    assert by_name["test greets the world"].duration == 4

    assert by_name["test greets the world in Portuguese"].suite_name == "greetings"

    assert by_name["test stumbles"].status == "failure"
    assert by_name["test stumbles"].suite_name in [nil, ""]
    assert by_name["test stumbles"].duration == 3

    assert by_name["test skipped for now"].status == "skipped"

    # And the per-test-run projection populates too, proving the module→case
    # granularity is written all the way down for dashboards to query.
    test_run_id = hd(test_case_runs).test_run_id

    projected =
      ClickHouseRepo.all(
        from(r in TestCaseRunByTestRun,
          where: r.test_run_id == ^test_run_id
        )
      )

    assert length(projected) == length(test_case_runs)
  end
end
