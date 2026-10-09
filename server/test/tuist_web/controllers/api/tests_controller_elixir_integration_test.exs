defmodule TuistWeb.API.TestsControllerElixirIntegrationTest do
  # End-to-end: drives the tuist_ex ExUnit formatter with synthetic
  # ExUnit.Test lifecycle events, posts what it reports to the real /tests
  # controller (no Mimic on Tuist.Tests), and asserts that ClickHouse
  # ends up with granular test_case_run rows.
  use TuistTestSupport.Cases.ConnCase, async: true

  import Ecto.Query
  import Phoenix.ConnTest

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunByTestRun
  alias TuistEx.Analytics.Enumeration
  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
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

  # The plugin hands its report to the test, which posts it. The request is
  # then made by the process that owns the database connections, so the test
  # needs no shared state and can run next to others.
  defp report_to(test), do: fn payload, _opts -> send(test, {:report, payload}) && :ok end

  defp environment("GIT_BRANCH"), do: "main"
  defp environment("GIT_COMMIT"), do: "0000000000000000000000000000000000000000"
  defp environment("GIT_REMOTE_URL"), do: "https://github.com/acme/widgets.git"
  defp environment(_name), do: nil

  defp post_report(conn, user, project) do
    assert_receive {:report, payload}, 5_000
    post(conn, "/api/projects/#{user.account.name}/#{project.name}/tests", payload)
  end

  test "tells the page waiting for a Mix project that the user reached it", %{conn: conn, user: user} do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :mix)
    Tuist.PubSub.subscribe("projects.#{project.id}")

    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: report_to(self()), environment: &environment/1)

    for event <- [{:suite_started, []}, {:test_finished, new_test([])}, {:suite_finished, %{run: 1_000}}],
        do: GenServer.cast(pid, event)

    assert conn |> post_report(user, project) |> json_response(:ok)

    user_id = user.id
    assert_receive {:show, %{user: %{id: ^user_id}}}
  end

  test "posts an ExUnit run and lands test_case_run rows in ClickHouse with per-case granularity",
       %{
         conn: conn,
         user: user,
         project: project
       } do
    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: report_to(self()), environment: &environment/1)

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
         state: {:failed, [{:error, %RuntimeError{message: "boom in greeter"}, stacktrace}]},
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
    :ok = GenServer.stop(pid)
    assert %{status: 200} = post_report(conn, user, project)

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
             "greets the world",
             "greets the world in Portuguese",
             "skipped for now",
             "stumbles"
           ]

    by_name = Map.new(test_case_runs, &{&1.name, &1})

    assert by_name["greets the world"].status == "success"
    assert by_name["greets the world"].suite_name == "greetings"
    assert by_name["greets the world"].duration == 4

    assert by_name["greets the world in Portuguese"].suite_name == "greetings"

    assert by_name["stumbles"].status == "failure"
    assert by_name["stumbles"].suite_name in [nil, ""]
    assert by_name["stumbles"].duration == 3

    assert by_name["skipped for now"].status == "skipped"

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

  test "records a Mix run's enumerated tests under the ids its test case runs carry", %{
    conn: conn,
    user: user,
    project: project
  } do
    # How `mix tuist.test --cover` reports: deferred, then completed and sent.
    # Its own `submit` keeps it from taking the options of the run that tests
    # this suite, such as its shard plan.
    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        submit: report_to(self()),
        mode: {:defer, self()},
        enumerate: true
      )

    events = [
      {:suite_started, []},
      {:test_finished,
       new_test(
         name: :"test cart adds an item",
         module: ShopTest,
         tags: %{describe: "cart", test_type: :test, file: "test/shop_test.exs", line: 3}
       )},
      {:test_finished,
       new_test(
         name: :"test ships",
         module: ShopTest,
         state: {:excluded, "due to only filter"},
         tags: %{describe: nil, test_type: :test, file: "test/shop_test.exs", line: 9}
       )},
      {:suite_finished, %{run: 1_000}}
    ]

    Enum.each(events, &GenServer.cast(pid, &1))
    :ok = GenServer.stop(pid)

    assert [{payload, _opts, false}] = ExUnitFormatter.take_deferred()
    {enumeration, payload} = Map.pop(payload, :enumeration)
    payload = Map.put(payload, :enumerated_tests, Enumeration.complete(enumeration, false))

    conn = post(conn, "/api/projects/#{user.account.name}/#{project.name}/tests", payload)
    assert %{"id" => test_run_id} = json_response(conn, 200)

    assert [
             %{module_name: "ShopTest", suite_name: "", name: "ships"},
             %{module_name: "ShopTest", suite_name: "cart", name: "adds an item", test_case_id: ran_id}
           ] = CoverageFixtures.enumerated_tests(%{id: test_run_id, project_id: project.id})

    assert [%{name: "adds an item", test_case_id: ^ran_id}] =
             ClickHouseRepo.all(from(r in TestCaseRun, where: r.test_run_id == ^test_run_id))
  end

  test "flags a failure as flaky when the same test also passed on the commit in CI", %{
    conn: conn,
    user: user,
    project: project
  } do
    environment = fn
      "CI" -> "true"
      "GIT_COMMIT" -> "5f2c1e9a7b3d4c6e8f0a1b2c3d4e5f6a7b8c9d0e"
      name -> environment(name)
    end

    run = fn state ->
      {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: report_to(self()), environment: environment)

      Enum.each(
        [
          {:suite_started, [max_cases: 8]},
          {:test_finished,
           new_test(
             name: :"test delivery retries on a timeout",
             module: FlakyDeliveryTest,
             state: state,
             time: 2_000,
             tags: %{describe: "delivery", test_type: :test, file: "test/flaky_delivery_test.exs", line: 3}
           )},
          {:suite_finished, %{run: 2_000, load: 100}}
        ],
        &GenServer.cast(pid, &1)
      )

      :ok = GenServer.stop(pid)
      assert %{status: 200} = post_report(conn, user, project)
    end

    runs = fn ->
      ClickHouseRepo.all(
        from(r in TestCaseRun,
          where: r.module_name == ^"FlakyDeliveryTest",
          group_by: r.id,
          select: %{
            status: fragment("argMax(?, ?)", r.status, r.inserted_at),
            is_flaky: fragment("argMax(?, ?)", r.is_flaky, r.inserted_at)
          }
        )
      )
    end

    run.(nil)
    assert [%{is_flaky: false}] = runs.()

    # The same test fails on a rerun of the commit: a failure that does not
    # reproduce. Only the failing run is flagged. (When the failure comes
    # first, the server flags it afterwards through a background job.)
    run.({:failed, [{:error, %RuntimeError{message: "timed out"}, []}]})

    assert %{"failure" => true, "success" => false} = Map.new(runs.(), &{to_string(&1.status), &1.is_flaky})
  end

  test "merges the shards of a Mix test run into one run", %{conn: conn, user: user, project: project} do
    %{plan: plan, shard_count: 2} =
      Tuist.Shards.create_shard_plan(project, %{
        reference: "mix-shards-#{System.unique_integer([:positive])}",
        modules: ["AccountsTest", "OrdersTest"],
        shard_total: 2
      })

    report = fn shard_index, module, status ->
      post(conn, "/api/projects/#{user.account.name}/#{project.name}/tests", %{
        id: UUIDv7.generate(),
        build_system: "mix",
        duration: 100,
        # The plugin reports when the run started, with a zone.
        ran_at: "2026-10-02T07:55:49.022154Z",
        is_ci: true,
        status: status,
        shard_plan_id: plan.id,
        shard_index: shard_index,
        test_modules: [
          %{name: module, status: status, duration: 100, test_cases: [%{name: "works", status: status, duration: 100}]}
        ]
      })
    end

    assert %{status: 200} = report.(0, "AccountsTest", "success")
    assert %{status: 200} = report.(1, "OrdersTest", "failure")

    shard_runs =
      ClickHouseRepo.all(
        from(r in Tuist.Shards.ShardRun,
          where: r.shard_plan_id == ^plan.id,
          select: {r.shard_index, r.test_run_id}
        )
      )

    # Both shards report into the same test run.
    assert [0, 1] = shard_runs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    assert [_one_run] = shard_runs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    assert ["AccountsTest", "OrdersTest"] =
             from(r in TestCaseRun, where: r.project_id == ^project.id, select: r.module_name, distinct: true)
             |> ClickHouseRepo.all()
             |> Enum.sort()
  end
end
