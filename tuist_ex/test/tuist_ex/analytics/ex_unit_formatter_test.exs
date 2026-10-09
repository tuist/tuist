defmodule TuistEx.Analytics.ExUnitFormatterTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.ExUnitFormatter

  # A fixed environment, so building a payload never asks git about the
  # checkout the tests happen to run in.
  defp environment("GIT_BRANCH"), do: "main"
  defp environment("GIT_COMMIT"), do: "0000000000000000000000000000000000000000"
  defp environment("GIT_REMOTE_URL"), do: "https://github.com/acme/widgets.git"
  defp environment(_name), do: nil

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

  defp send_lifecycle(pid, events) do
    Enum.each(events, &GenServer.cast(pid, &1))
  end

  defp capture_state(pid) do
    :sys.get_state(pid)
  end

  test "names a test by its own name, without ExUnit's type and describe prefixes" do
    described =
      new_test(
        name: :"test create_order/2 rejects an empty cart",
        tags: %{describe: "create_order/2", test_type: :test, file: "test/some_test.exs", line: 1}
      )

    assert %{name: "rejects an empty cart", describe: "create_order/2"} =
             ExUnitFormatter.record(described)

    property =
      new_test(
        name: :"property sorting is idempotent",
        tags: %{describe: nil, test_type: :property}
      )

    assert ExUnitFormatter.record(property).name == "sorting is idempotent"

    # A name that merely starts with the word is left alone after the prefix.
    assert ExUnitFormatter.record(new_test(name: :"test test helpers work")).name ==
             "test helpers work"
  end

  test "reports a failure without a source location without a null path" do
    timed_out = new_test(state: {:failed, [{:error, %RuntimeError{message: "timed out"}, []}]})
    assert [failure] = ExUnitFormatter.record(timed_out).failures

    assert failure == %{
             message: "** (RuntimeError) timed out",
             line_number: 0,
             issue_type: "error_thrown"
           }

    assert [%{message: "Setup failed for SomeModuleTest"} = setup_failure] =
             ExUnitFormatter.record(new_test(state: {:invalid, SomeModuleTest})).failures

    refute Map.has_key?(setup_failure, :path)
  end

  describe "merge_retries/2" do
    defp payload do
      %{
        status: "failure",
        test_modules: [
          %{
            name: "OrdersTest",
            status: "failure",
            duration: 30,
            test_suites: [%{name: "create_order/2", status: "failure", duration: 30}],
            test_cases: [
              %{
                name: "rejects an empty cart",
                test_suite_name: "create_order/2",
                status: "failure",
                duration: 10,
                failures: [%{message: "timed out", line_number: 0, issue_type: "error_thrown"}]
              },
              %{name: "is broken", status: "failure", duration: 10, failures: []},
              %{name: "passes", status: "success", duration: 10, failures: []}
            ]
          }
        ]
      }
    end

    defp attempt(name, describe, status) do
      %{
        module: "OrdersTest",
        describe: describe,
        name: name,
        status: status,
        duration_ms: 7,
        failures: []
      }
    end

    test "reports a test that passes on a retry as successful, with every attempt" do
      first = [
        attempt("rejects an empty cart", "create_order/2", "failure"),
        attempt("is broken", nil, "failure")
      ]

      second = [
        attempt("rejects an empty cart", "create_order/2", "success"),
        attempt("is broken", nil, "failure")
      ]

      merged = ExUnitFormatter.merge_retries(payload(), [first, second])
      [module] = merged.test_modules
      [flaky, broken, passing] = module.test_cases

      assert flaky.status == "success"
      assert flaky.duration == 24
      # The two retries of the two retried tests add 28ms to the module and
      # 14ms to the suite holding one of them.
      assert module.duration == 30 + 28
      assert [%{duration: 44}] = module.test_suites

      assert flaky.repetitions == [
               %{repetition_number: 1, name: "Run 1", status: "failure", duration: 10},
               %{repetition_number: 2, name: "Retry 1", status: "failure", duration: 7},
               %{repetition_number: 3, name: "Retry 2", status: "success", duration: 7}
             ]

      # The failure of the first run is kept, so the page can show why it flaked.
      assert [%{message: "timed out"}] = flaky.failures

      assert broken.status == "failure"
      assert length(broken.repetitions) == 3
      refute Map.has_key?(passing, :repetitions)

      # The suite recovered; the module and the run still have a broken test.
      assert [%{name: "create_order/2", status: "success"}] = module.test_suites
      assert module.status == "failure"
      assert merged.status == "failure"
    end

    test "turns the run green when every failed test passes on a retry" do
      retried = [
        attempt("rejects an empty cart", "create_order/2", "success"),
        attempt("is broken", nil, "success")
      ]

      merged = ExUnitFormatter.merge_retries(payload(), [retried])

      assert merged.status == "success"
      assert [%{status: "success"}] = merged.test_modules
    end

    test "leaves a run without retries untouched" do
      assert ExUnitFormatter.merge_retries(payload(), []) == payload()
      assert ExUnitFormatter.merge_retries(payload(), [[]]) == payload()
    end

    test "adds the time the retries took to the run" do
      retried = [attempt("is broken", nil, "failure")]

      assert ExUnitFormatter.merge_retries(Map.put(payload(), :duration, 100), [retried]).duration ==
               107
    end
  end

  test "keeps every suite of an umbrella in defer mode, and notes one that stopped early" do
    submit = fn _payload, _opts -> :ok end

    for events <- [
          [
            {:suite_started, []},
            {:test_finished, new_test(module: AlphaTest)},
            {:suite_finished, %{run: 1_000}}
          ],
          [
            {:suite_started, []},
            {:test_finished, new_test(module: BetaTest)},
            :max_failures_reached,
            {:suite_finished, %{run: 1_000}}
          ]
        ] do
      {:ok, pid} =
        GenServer.start_link(ExUnitFormatter,
          environment: &environment/1,
          submit: submit,
          mode: {:defer, self()}
        )

      send_lifecycle(pid, events)
      :ok = GenServer.stop(pid)
    end

    assert [
             {%{test_modules: [%{name: "AlphaTest"}]}, _, false},
             {%{test_modules: [%{name: "BetaTest"}]}, _, true}
           ] = ExUnitFormatter.take_deferred()
  end

  describe "enumerated tests" do
    defp deferred_run(events, opts) do
      {:ok, pid} =
        GenServer.start_link(
          ExUnitFormatter,
          [environment: &environment/1, mode: {:defer, self()}] ++ opts
        )

      send_lifecycle(pid, [{:suite_started, []}] ++ events ++ [{:suite_finished, %{run: 1_000}}])
      :ok = GenServer.stop(pid)
      assert [{payload, _opts, _aborted?}] = ExUnitFormatter.take_deferred()
      payload
    end

    defp described(name, describe) do
      new_test(
        name: :"test #{describe} #{name}",
        tags: %{describe: describe, test_type: :test, file: "test/some_test.exs", line: 1}
      )
    end

    test "lists every test of a full run, as its test cases identify it" do
      payload =
        deferred_run(
          [
            {:test_finished, described("rejects an empty cart", "create_order/2")},
            {:test_finished, new_test(name: :"test adds", state: {:failed, []})}
          ],
          enumerate: true
        )

      assert %{tests: tests, project: %{files: files}} = payload.enumeration
      assert is_list(files)

      assert tests == [
               %{
                 module: "SomeModuleTest",
                 suite: "create_order/2",
                 name: "rejects an empty cart"
               },
               %{module: "SomeModuleTest", suite: "", name: "adds"}
             ]
    end

    test "lists the tests a filter such as --only left out, without reporting them as run" do
      payload =
        deferred_run(
          [
            {:test_finished, new_test(name: :"test selected")},
            {:test_finished, new_test(name: :"test left out", state: {:excluded, "due to only"})}
          ],
          enumerate: true
        )

      assert [%{test_cases: [%{name: "selected"}]}] = payload.test_modules

      assert Enum.map(payload.enumeration.tests, & &1.name) == ["selected", "left out"]
    end

    test "lists nothing unless asked" do
      payload = deferred_run([{:test_finished, new_test([])}], [])
      refute Map.has_key?(payload, :enumeration)
    end
  end

  test "reports the execution variant as the run scheme" do
    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        scheme: "clickhouse-floor",
        mode: {:defer, self()}
      )

    send_lifecycle(pid, [
      {:suite_started, []},
      {:test_finished, new_test([])},
      {:suite_finished, %{run: 1_000}}
    ])

    :ok = GenServer.stop(pid)
    assert [{%{scheme: "clickhouse-floor"}, _, false}] = ExUnitFormatter.take_deferred()
  end

  test "keeps the run for the caller in defer mode and writes outcomes to a file in collect mode" do
    parent = self()
    submit = fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end

    events = [
      {:suite_started, []},
      {:test_finished, new_test([])},
      {:suite_finished, %{run: 1_000}}
    ]

    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        submit: submit,
        mode: {:defer, self()}
      )

    send_lifecycle(pid, events)
    :ok = GenServer.stop(pid)

    refute_received {:submitted, _}
    assert [{%{test_modules: [_]}, opts, false}] = ExUnitFormatter.take_deferred()
    assert ExUnitFormatter.take_deferred() == []
    assert :ok = ExUnitFormatter.submit(%{}, opts)
    assert_received {:submitted, %{}}

    path = Path.join(System.tmp_dir!(), "tuist-ex-collect-#{System.unique_integer([:positive])}")

    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        submit: submit,
        mode: {:collect, path}
      )

    send_lifecycle(pid, events)
    :ok = GenServer.stop(pid)

    refute_received {:submitted, _}
    assert [%{name: "example", status: "success"}] = ExUnitFormatter.read_collected(path)

    # An umbrella runs a suite per application: each adds to the same file.
    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        submit: submit,
        mode: {:collect, path}
      )

    send_lifecycle(pid, events)
    :ok = GenServer.stop(pid)
    assert length(ExUnitFormatter.read_collected(path)) == 2
    File.rm(path)
    assert ExUnitFormatter.read_collected(path) == []
  end

  test "a formatter given its own submit function ignores the options of the surrounding run" do
    configured = [mode: {:defer, self()}, project: "acme/widgets"]
    submit = fn _payload, _opts -> :ok end

    assert ExUnitFormatter.run_options([submit: submit], configured) == [submit: submit]

    # The one ExUnit starts for the run gets them, and its own options win.
    run = ExUnitFormatter.run_options([seed: 1, project: "other/app"], configured)
    assert run[:mode] == {:defer, self()}
    assert run[:project] == "other/app"
    assert run[:seed] == 1
  end

  test "records a passing test as success" do
    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        submit: fn _payload, _opts -> :ok end
      )

    GenServer.cast(pid, {:test_finished, new_test([])})
    assert [record] = capture_state(pid).tests
    assert record.status == "success"
    assert record.duration_ms == 1
    assert record.failures == []
    :ok = GenServer.stop(pid)
  end

  test "maps ExUnit outcomes onto success/failure/skipped" do
    assert %{status: "success"} = ExUnitFormatter.record(new_test(state: nil))

    assert %{status: "failure"} =
             ExUnitFormatter.record(
               new_test(
                 state: {:failed, [{:error, %RuntimeError{message: "boom"}, []}]},
                 tags: %{describe: "when broken", file: "test/x_test.exs", line: 5}
               )
             )

    assert %{status: "failure"} = ExUnitFormatter.record(new_test(state: {:invalid, SomeModule}))
    assert %{status: "skipped"} = ExUnitFormatter.record(new_test(state: {:skipped, "reason"}))
  end

  test "extracts failure location and assertion issue type" do
    stacktrace = [
      {SomeModuleTest, :"test example", 1, [file: ~c"test/some_test.exs", line: 42]}
    ]

    test =
      new_test(
        state: {:failed, [{:error, %ExUnit.AssertionError{message: "not equal"}, stacktrace}]},
        tags: %{describe: nil, file: "test/some_test.exs", line: 1}
      )

    assert %{failures: [failure]} = ExUnitFormatter.record(test)
    assert failure.line_number == 42
    assert failure.path == "test/some_test.exs"
    assert failure.issue_type == "assertion_failure"
  end

  test "builds the wire payload and submits at suite_finished" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter, environment: &environment/1, submit: submit)

    events = [
      {:suite_started, [max_cases: 8]},
      {:test_finished,
       new_test(
         name: :"test greets the world",
         module: GreeterTest,
         time: 2_000,
         tags: %{describe: "greetings", file: "test/greeter_test.exs", line: 3}
       )},
      {:test_finished,
       new_test(
         name: :"test stumbles",
         module: GreeterTest,
         state: {:failed, [{:error, %RuntimeError{message: "boom"}, []}]},
         time: 3_000,
         tags: %{describe: nil, file: "test/greeter_test.exs", line: 20}
       )},
      {:suite_finished, %{run: 5_000, load: 100}}
    ]

    send_lifecycle(pid, events)

    assert_receive {:submitted, payload}, 2000
    assert payload.build_system == "mix"
    assert payload.contract_version
    assert payload.duration == 5
    assert payload.status == "failure"

    assert [module] = payload.test_modules
    assert module.name == "GreeterTest"
    assert module.status == "failure"
    assert module.duration == 5

    assert Enum.any?(module.test_cases, &(&1.name == "greets the world"))
    assert Enum.any?(module.test_suites, &(&1.name == "greetings"))

    :ok = GenServer.stop(pid)
  end

  test "aggregates an all-skipped module as success so the server accepts the payload" do
    # The server schema only permits success/failure at the module level, so
    # even when every case is skipped the module aggregate must stay success.
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter, environment: &environment/1, submit: submit)

    events = [
      {:suite_started, []},
      {:test_finished,
       new_test(
         name: :"test skipped one",
         module: OnlySkippedTest,
         state: {:skipped, "not ready"},
         time: 0,
         tags: %{describe: nil, file: "test/only_skipped_test.exs", line: 1}
       )},
      {:test_finished,
       new_test(
         name: :"test skipped two",
         module: OnlySkippedTest,
         state: {:excluded, "filtered"},
         time: 0,
         tags: %{describe: nil, file: "test/only_skipped_test.exs", line: 5}
       )},
      {:suite_finished, %{run: 1_000}}
    ]

    Enum.each(events, &GenServer.cast(pid, &1))

    assert_receive {:submitted, payload}, 2000
    assert [module] = payload.test_modules
    assert module.status == "success"
    # A test a filter excluded was not part of the run.
    assert [%{name: "skipped one", status: "skipped"}] = module.test_cases

    :ok = GenServer.stop(pid)
  end

  test "logs and swallows submission errors so mix test's exit code is unchanged" do
    parent = self()

    submit = fn _payload, _opts -> {:error, :nxdomain} end

    shell = fn message ->
      send(parent, {:shell, message})
      :ok
    end

    {:ok, pid} =
      GenServer.start_link(ExUnitFormatter,
        environment: &environment/1,
        submit: submit,
        shell: shell
      )

    GenServer.cast(pid, {:suite_started, []})
    GenServer.cast(pid, {:test_finished, new_test([])})
    GenServer.cast(pid, {:suite_finished, %{run: 1_000}})

    assert_receive {:shell, message}, 2000
    assert message =~ "failed to submit"

    :ok = GenServer.stop(pid)
  end
end
