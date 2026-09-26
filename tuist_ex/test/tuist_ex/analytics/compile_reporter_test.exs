defmodule TuistEx.Analytics.CompileReporterTest do
  use ExUnit.Case, async: false

  alias TuistEx.Analytics.CompileReporter

  setup do
    on_exit(fn ->
      case Process.whereis(CompileReporter) do
        pid when is_pid(pid) -> GenServer.stop(pid)
        _ -> :ok
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
end
