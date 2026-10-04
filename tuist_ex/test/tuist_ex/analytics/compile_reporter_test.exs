defmodule TuistEx.Analytics.CompileReporterTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.CompileReporter

  # A fixed environment, so building a payload never asks git about the
  # checkout the tests happen to run in.
  defp environment("GIT_BRANCH"), do: "main"
  defp environment("GIT_COMMIT"), do: "0000000000000000000000000000000000000000"
  defp environment("GIT_REMOTE_URL"), do: "https://github.com/acme/widgets.git"
  defp environment(_name), do: nil

  # Reads no machine unless a test asks for the sampler, so nothing global is
  # started; each reporter is the test's own.
  defp start(opts) do
    opts = opts |> Keyword.put_new(:sampler, nil) |> Keyword.put_new(:environment, &environment/1)
    start_supervised!({CompileReporter, opts}, id: make_ref())
  end

  test "records each compiler's diagnostics and submits a merged payload" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    reporter = start(submit: submit)

    diagnostic = %{
      severity: :warning,
      file: "lib/foo.ex",
      source: Foo,
      message: "unused variable",
      position: {12, 3}
    }

    CompileReporter.record(reporter, :elixir, {:ok, [diagnostic]})
    CompileReporter.record(reporter, :app, {:ok, []})
    :ok = CompileReporter.finish(reporter)

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "success"
    assert payload.duration_ms >= 0
    assert [d] = payload.diagnostics
    assert d.severity == "warning"
    assert d.file == "lib/foo.ex"
    assert d.module == "Foo"
    assert d.line == 12
    assert d.column == 3
    assert d.compiler == "elixir"
  end

  test "reports failure when a compiler returned :error even with no diagnostics" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    reporter = start(submit: submit)

    CompileReporter.record(reporter, :elixir, {:error, []})
    :ok = CompileReporter.finish(reporter)

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "failure"
  end

  test "reports failure when at least one diagnostic is an error" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    reporter = start(submit: submit)

    CompileReporter.record(
      reporter,
      :elixir,
      {:ok,
       [
         %{severity: :warning, file: "lib/a.ex", message: "warn"},
         %{severity: :error, file: "lib/b.ex", message: "boom"}
       ]}
    )

    :ok = CompileReporter.finish(reporter)

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "failure"
    assert Enum.any?(payload.diagnostics, &(&1.severity == "error"))
  end

  test "collects the samples its machine sampler sends" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    sample = fn rates ->
      Map.merge(%{timestamp: 1.0, cpu_usage_percent: 12.5, memory_total_bytes: 64}, rates)
    end

    counters = fn -> %{network: nil, disk: nil} end

    reporter =
      start(
        submit: submit,
        sampler: :auto,
        sampler_opts: [interval_ms: 10, sample: sample, counters: counters]
      )

    # Sent by the sampler, then acknowledged here: `finish/3` is handled after it.
    :erlang.trace(reporter, true, [:receive])

    assert_receive {:trace, ^reporter, :receive, {:machine_metric, %{cpu_usage_percent: 12.5}}},
                   2000

    CompileReporter.record(reporter, :elixir, {:ok, []})
    :ok = CompileReporter.finish(reporter)

    assert_receive {:submitted, payload}, 2000
    assert [%{cpu_usage_percent: _, memory_total_bytes: _} | _] = payload.machine_metrics
  end

  test "includes the per-file profile it is finished with" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    reporter = start(submit: submit, sampler: nil)

    files = [
      %{path: "lib/a.ex", compile_duration_ms: 5, wait_duration_ms: 0, modules: ["A"], waits: []}
    ]

    :ok = CompileReporter.finish(reporter, files)

    assert_receive {:submitted, payload}, 2000
    assert payload.files == files
  end

  test "logs and swallows submission failures without raising" do
    parent = self()
    submit = fn _payload, _opts -> {:error, :nxdomain} end

    shell = fn message ->
      send(parent, {:shell, message})
      :ok
    end

    reporter = start(submit: submit, shell: shell)

    CompileReporter.record(reporter, :elixir, {:ok, []})
    :ok = CompileReporter.finish(reporter)

    assert_receive {:shell, message}, 2000
    assert message =~ "failed to submit compile run"
  end

  @tag :capture_log
  test "a submission that raises costs the report, not the build" do
    parent = self()

    reporter =
      start(
        submit: fn _payload, _opts -> raise "credentials could not be saved" end,
        shell: fn message -> send(parent, {:shell, message}) && :ok end
      )

    CompileReporter.record(reporter, :elixir, {:ok, []})
    assert :ok = CompileReporter.finish(reporter)
    assert_receive {:shell, message}, 2000
    assert message =~ "credentials could not be saved"
  end

  test "a reporter that is not linked stops with the build that started it" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, reporter} = CompileReporter.start(sampler: nil, environment: &environment/1)
        send(parent, {:reporter, reporter})
        Process.sleep(:infinity)
      end)

    assert_receive {:reporter, reporter}, 2000
    reference = Process.monitor(reporter)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^reference, :process, ^reporter, :normal}, 2000
  end

  test "trims a report whose fields fit but whose whole does not" do
    parent = self()

    reporter =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        max_payload_bytes: 20_000
      )

    files =
      for index <- 1..400 do
        %{
          path: "lib/f#{index}.ex",
          compile_duration_ms: index,
          modules: [],
          waits: [],
          dependencies: []
        }
      end

    :ok = CompileReporter.finish(reporter, files)

    assert_receive {:submitted, payload}, 2000
    assert byte_size(Jason.encode!(payload)) <= 20_000
    assert payload.files != []
    assert hd(payload.files).path == "lib/f400.ex"
  end

  test "reports nothing when every compiler had nothing to do" do
    parent = self()

    reporter =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        sampler: nil
      )

    CompileReporter.record(reporter, :elixir, {:noop, []})
    CompileReporter.record(reporter, :app, {:noop, []})
    :ok = CompileReporter.finish(reporter)

    refute_receive {:submitted, _}, 200
  end

  test "reports nothing when no compiler ran" do
    # `mix test --no-compile`, which every test shard runs.
    parent = self()

    reporter =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        sampler: nil
      )

    :ok = CompileReporter.finish(reporter)

    refute_receive {:submitted, _}, 200
  end

  test "names a diagnostic after the compiler that produced it" do
    # An umbrella's root hands over what its apps' compilers returned.
    parent = self()

    reporter =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        sampler: nil
      )

    diagnostic = %{
      severity: :warning,
      message: "unused",
      file: "lib/a.ex",
      compiler_name: "Erlang"
    }

    CompileReporter.record(reporter, :compile, {:noop, [diagnostic]})
    :ok = CompileReporter.finish(reporter, [%{path: "lib/a.ex", compile_duration_ms: 1}])

    assert_receive {:submitted, %{diagnostics: [%{compiler: "erlang"}]}}, 2000
  end

  test "reports a failure in a compiler other than Elixir's" do
    parent = self()

    reporter =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        sampler: nil
      )

    # The Erlang compiler fails, so the Elixir and application compilers never run.
    CompileReporter.record(
      reporter,
      :erlang,
      {:error,
       [
         %{
           severity: :error,
           file: "src/broken.erl",
           message: "syntax error before: '.'",
           position: 3
         }
       ]}
    )

    :ok = CompileReporter.finish(reporter)

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "failure"

    assert [%{compiler: "erlang", file: "src/broken.erl", severity: "error"}] =
             payload.diagnostics
  end

  test "a finished build takes its reporter with it, so the next build starts clean" do
    parent = self()
    submit = fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end

    first = start(submit: submit, sampler: nil)
    reference = Process.monitor(first)

    CompileReporter.record(
      first,
      :elixir,
      {:error, [%{severity: :error, file: "lib/a.ex", message: "boom", position: 1}]}
    )

    :ok = CompileReporter.finish(first)
    assert_receive {:submitted, %{status: "failure"}}, 2000
    assert_receive {:DOWN, ^reference, :process, ^first, _reason}, 2000

    second = start(submit: submit, sampler: nil)
    assert second != first
    CompileReporter.record(second, :elixir, {:ok, []})
    :ok = CompileReporter.finish(second)

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "success"
    assert payload.diagnostics == []
  end

  test "trims an oversized build to what the server accepts, keeping the slowest files" do
    parent = self()

    reporter =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        sampler: nil
      )

    for second <- 1..20_500, do: send(reporter, {:machine_metric, %{timestamp: second * 1.0}})

    files =
      for index <- 1..20_010 do
        %{
          path: "lib/f#{index}.ex",
          compile_duration_ms: index,
          wait_duration_ms: 0,
          modules: [],
          waits: [],
          dependencies: []
        }
      end

    too_long = %{
      path: String.duplicate("a", 2_000),
      compile_duration_ms: 99_999,
      modules: [],
      waits: [],
      dependencies: []
    }

    CompileReporter.record(
      reporter,
      :elixir,
      {:ok,
       [
         %{
           severity: :warning,
           file: "lib/a.ex",
           message: String.duplicate("m", 20_000),
           position: 1
         }
       ]}
    )

    :ok = CompileReporter.finish(reporter, [too_long | files])

    assert_receive {:submitted, payload}, 5000
    assert length(payload.files) == 20_000
    assert hd(payload.files).path == "lib/f20010.ex"
    refute Enum.any?(payload.files, &(&1.path == "lib/f1.ex"))
    assert length(payload.machine_metrics) <= 20_000
    assert List.last(payload.machine_metrics).timestamp > 20_000
    assert [%{message: message}] = payload.diagnostics
    assert String.length(message) == 10_000
  end
end
