defmodule TuistEx.Analytics.CompileReporterTest do
  use ExUnit.Case, async: false

  alias TuistEx.Analytics.CompileReporter

  setup do
    on_exit(fn ->
      case Process.whereis(CompileReporter) do
        pid when is_pid(pid) ->
          # The reporter is linked to the test process, so it may already be
          # going down by the time this runs.
          try do
            GenServer.stop(pid)
          catch
            :exit, _ -> :ok
          end

        _ ->
          :ok
      end
    end)
  end

  defp start(opts) do
    {:ok, pid} =
      case CompileReporter.start_link(opts) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
      end

    pid
  end

  test "records each compiler's diagnostics and submits a merged payload" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    start(submit: submit)

    diagnostic = %{
      severity: :warning,
      file: "lib/foo.ex",
      source: Foo,
      message: "unused variable",
      position: {12, 3}
    }

    CompileReporter.record(:elixir, {:ok, [diagnostic]})
    CompileReporter.record(:app, {:ok, []})
    :ok = CompileReporter.finish()

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

    start(submit: submit)

    CompileReporter.record(:elixir, {:error, []})
    :ok = CompileReporter.finish()

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "failure"
  end

  test "reports failure when at least one diagnostic is an error" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    start(submit: submit)

    CompileReporter.record(
      :elixir,
      {:ok,
       [
         %{severity: :warning, file: "lib/a.ex", message: "warn"},
         %{severity: :error, file: "lib/b.ex", message: "boom"}
       ]}
    )

    :ok = CompileReporter.finish()

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "failure"
    assert Enum.any?(payload.diagnostics, &(&1.severity == "error"))
  end

  test "collects samples from the real machine metrics sampler" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    start(submit: submit, sampler_opts: [interval_ms: 10])
    Process.sleep(500)
    assert Process.alive?(Process.whereis(CompileReporter))

    :ok = CompileReporter.finish()

    assert_receive {:submitted, payload}, 2000
    assert [%{cpu_usage_percent: _, memory_total_bytes: _} | _] = payload.machine_metrics
  end

  test "includes the per-file profile it is finished with" do
    parent = self()

    submit = fn payload, _opts ->
      send(parent, {:submitted, payload})
      :ok
    end

    start(submit: submit, sampler: nil)

    files = [
      %{path: "lib/a.ex", compile_duration_ms: 5, wait_duration_ms: 0, modules: ["A"], waits: []}
    ]

    :ok = CompileReporter.finish(files)

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

    start(submit: submit, shell: shell)

    CompileReporter.record(:elixir, {:ok, []})
    :ok = CompileReporter.finish()

    assert_receive {:shell, message}, 2000
    assert message =~ "failed to submit compile run"
  end

  test "reports nothing when every compiler had nothing to do" do
    parent = self()

    start(
      submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
      sampler: nil
    )

    CompileReporter.record(:elixir, {:noop, []})
    CompileReporter.record(:app, {:noop, []})
    :ok = CompileReporter.finish()

    refute_receive {:submitted, _}, 200
  end

  test "reports a failure in a compiler other than Elixir's" do
    parent = self()

    start(
      submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
      sampler: nil
    )

    # The Erlang compiler fails, so the Elixir and application compilers never run.
    CompileReporter.record(
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

    :ok = CompileReporter.finish()

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
      :elixir,
      {:error, [%{severity: :error, file: "lib/a.ex", message: "boom", position: 1}]}
    )

    :ok = CompileReporter.finish()
    assert_receive {:submitted, %{status: "failure"}}, 2000
    assert_receive {:DOWN, ^reference, :process, ^first, _reason}, 2000

    second = start(submit: submit, sampler: nil)
    assert second != first
    CompileReporter.record(:elixir, {:ok, []})
    :ok = CompileReporter.finish()

    assert_receive {:submitted, payload}, 2000
    assert payload.status == "success"
    assert payload.diagnostics == []
  end

  test "trims an oversized build to what the server accepts, keeping the slowest files" do
    parent = self()

    pid =
      start(
        submit: fn payload, _opts -> send(parent, {:submitted, payload}) && :ok end,
        sampler: nil
      )

    for second <- 1..20_500, do: send(pid, {:machine_metric, %{timestamp: second * 1.0}})

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

    :ok = CompileReporter.finish([too_long | files])

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
