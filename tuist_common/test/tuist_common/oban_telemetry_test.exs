defmodule TuistCommon.ObanTelemetryTest do
  use ExUnit.Case, async: false
  use Mimic

  setup :set_mimic_from_context

  setup do
    TuistCommon.ObanTelemetry.attach()

    on_exit(fn ->
      :telemetry.detach("oban-discard-error-reporter")
    end)
  end

  defp emit_exception(overrides) do
    defaults = %{
      state: :failure,
      job: %{
        id: 1,
        args: %{},
        queue: "default",
        worker: "MyApp.Worker",
        attempt: 1,
        max_attempts: 3,
        state: "executing",
        tags: []
      },
      kind: :error,
      reason: %RuntimeError{message: "boom"},
      stacktrace: []
    }

    :telemetry.execute(
      [:oban, :job, :exception],
      %{duration: 1000, queue_time: 0},
      Map.merge(defaults, overrides)
    )
  end

  describe "[:oban, :job, :exception] telemetry" do
    test "reports to Sentry when a job exhausts all attempts" do
      expect(Sentry, :capture_exception, fn exception, opts ->
        assert %RuntimeError{message: "boom"} = exception
        assert opts[:tags] == %{oban_worker: "MyApp.Worker", oban_queue: "default"}
        assert opts[:extra][:attempt] == 3
        assert opts[:extra][:max_attempts] == 3
        {:ok, "event-id"}
      end)

      emit_exception(%{
        state: :discard,
        job: %{
          id: 1,
          args: %{},
          queue: "default",
          worker: "MyApp.Worker",
          attempt: 3,
          max_attempts: 3,
          state: "executing",
          tags: []
        }
      })
    end

    test "does not report to Sentry when a job has remaining attempts" do
      reject(&Sentry.capture_exception/2)

      emit_exception(%{state: :failure})
    end
  end
end
