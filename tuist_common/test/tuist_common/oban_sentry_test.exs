defmodule TuistCommon.ObanSentryTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistCommon.ObanSentry

  setup :set_mimic_from_context

  defp job_struct(overrides) do
    Map.merge(
      %{
        id: 1,
        args: %{},
        queue: "default",
        worker: "MyApp.Worker",
        attempt: 1,
        max_attempts: 3,
        state: "executing",
        tags: []
      },
      overrides
    )
  end

  describe "handle_event/4" do
    test "reports to Sentry when job is discarded" do
      reason = %RuntimeError{message: "boom"}

      expect(Sentry, :capture_exception, fn exception, opts ->
        assert %RuntimeError{message: "boom"} = exception
        assert opts[:tags] == %{oban_worker: "MyApp.Worker", oban_queue: "default"}
        assert opts[:extra][:attempt] == 3
        assert opts[:extra][:max_attempts] == 3
        {:ok, "event-id"}
      end)

      ObanSentry.handle_event(
        [:oban, :job, :exception],
        %{duration: 1000},
        %{
          state: :discard,
          job: job_struct(%{attempt: 3, max_attempts: 3}),
          kind: :error,
          reason: reason,
          stacktrace: []
        },
        :no_config
      )
    end

    test "does not report to Sentry when job will be retried" do
      reject(&Sentry.capture_exception/2)

      ObanSentry.handle_event(
        [:oban, :job, :exception],
        %{duration: 1000},
        %{
          state: :failure,
          job: job_struct(%{attempt: 1, max_attempts: 3}),
          kind: :error,
          reason: %RuntimeError{message: "boom"},
          stacktrace: []
        },
        :no_config
      )
    end
  end
end
