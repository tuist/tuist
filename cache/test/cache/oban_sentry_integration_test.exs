defmodule Cache.ObanSentryIntegrationTest do
  use ExUnit.Case, async: false
  use Mimic
  use Oban.Testing, repo: Cache.Repo

  alias Ecto.Adapters.SQL.Sandbox

  setup :set_mimic_from_context

  setup do
    :ok = Sandbox.checkout(Cache.Repo)
    :ok
  end

  defmodule FailingWorker do
    use Oban.Worker, queue: :test, max_attempts: 1

    @impl Oban.Worker
    def perform(_job), do: raise("job failed permanently")
  end

  describe "discarded Oban job" do
    test "reports to Sentry when a job exhausts all attempts" do
      test_pid = self()

      expect(Sentry, :capture_exception, fn exception, opts ->
        send(test_pid, {:sentry_called, exception, opts})
        {:ok, "event-id"}
      end)

      assert_raise RuntimeError, "job failed permanently", fn ->
        perform_job(FailingWorker, %{})
      end

      assert_received {:sentry_called, exception, opts}
      assert %RuntimeError{message: "job failed permanently"} = exception
      assert opts[:tags][:oban_worker] == "Cache.ObanSentryIntegrationTest.FailingWorker"
      assert opts[:tags][:oban_queue] == "test"
      assert opts[:extra][:attempt] == 1
      assert opts[:extra][:max_attempts] == 1
    end

    test "does not report to Sentry when a job has remaining attempts" do
      reject(&Sentry.capture_exception/2)

      assert_raise RuntimeError, fn ->
        perform_job(FailingWorker, %{}, max_attempts: 5)
      end
    end
  end
end
