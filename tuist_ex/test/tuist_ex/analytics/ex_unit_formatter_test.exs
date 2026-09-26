defmodule TuistEx.Analytics.ExUnitFormatterTest do
  use ExUnit.Case, async: false

  alias TuistEx.Analytics.ExUnitFormatter

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

  test "records a passing test as success" do
    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: fn _payload, _opts -> :ok end)
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
    assert %{status: "skipped"} = ExUnitFormatter.record(new_test(state: {:excluded, "reason"}))
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

    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: submit)

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

    assert Enum.any?(module.test_cases, &(&1.name == "test greets the world"))
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

    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: submit)

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

    :ok = GenServer.stop(pid)
  end

  test "logs and swallows submission errors so mix test's exit code is unchanged" do
    parent = self()

    submit = fn _payload, _opts -> {:error, :nxdomain} end

    shell = fn message ->
      send(parent, {:shell, message})
      :ok
    end

    {:ok, pid} = GenServer.start_link(ExUnitFormatter, submit: submit, shell: shell)

    GenServer.cast(pid, {:suite_started, []})
    GenServer.cast(pid, {:test_finished, new_test([])})
    GenServer.cast(pid, {:suite_finished, %{run: 1_000}})

    assert_receive {:shell, message}, 2000
    assert message =~ "failed to submit"

    :ok = GenServer.stop(pid)
  end
end
