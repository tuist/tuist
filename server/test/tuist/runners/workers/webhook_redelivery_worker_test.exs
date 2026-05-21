defmodule Tuist.Runners.Workers.WebhookRedeliveryWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.GitHub.Client, as: GitHubClient
  alias Tuist.Runners.Workers.WebhookRedeliveryWorker

  setup :verify_on_exit!

  defp delivery(opts) do
    %{
      id: Keyword.get(opts, :id, 1_000_001),
      guid: Keyword.get(opts, :guid, "guid-1"),
      delivered_at: Keyword.get(opts, :delivered_at, DateTime.add(DateTime.utc_now(), -120, :second)),
      redelivery: Keyword.get(opts, :redelivery, false),
      status: Keyword.get(opts, :status, "Internal Server Error"),
      status_code: Keyword.get(opts, :status_code, 500),
      event: Keyword.get(opts, :event, "workflow_job"),
      action: Keyword.get(opts, :action, "queued"),
      installation_id: Keyword.get(opts, :installation_id, 42),
      repository_id: Keyword.get(opts, :repository_id, 100)
    }
  end

  defp page(deliveries, opts \\ []) do
    {:ok, %{meta: %{next_url: Keyword.get(opts, :next_url)}, deliveries: deliveries}}
  end

  describe "perform/1" do
    test "is a no-op when GitHub reports no failed deliveries" do
      expect(GitHubClient, :list_app_hook_deliveries, fn opts ->
        assert Keyword.get(opts, :status) == "failure"
        page([])
      end)

      reject(&GitHubClient.redeliver_app_hook_delivery/1)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "asks GitHub to redeliver a failed workflow_job delivery" do
      failed = delivery(id: 7_001, guid: "g-1", status_code: 500)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([failed]) end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id ->
        assert id == failed.id
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "skips a GUID whose attempts include any successful one" do
      # The successful redelivery from a previous cycle. GitHub's
      # documented dedup pattern: if any attempt for this GUID was
      # OK, we're done.
      guid = "g-dedup"

      original_failure = delivery(id: 1, guid: guid, status_code: 500, delivered_at: ts_ago(300))

      successful_redelivery =
        delivery(id: 2, guid: guid, status_code: 200, status: "OK", redelivery: true, delivered_at: ts_ago(60))

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts ->
        page([successful_redelivery, original_failure])
      end)

      reject(&GitHubClient.redeliver_app_hook_delivery/1)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "skips deliveries that are not workflow_job events" do
      # Push events, PR events, etc. share the App's delivery log
      # but are not in scope for runners recovery.
      push_failure = delivery(id: 9_001, guid: "g-push", event: "push", action: nil)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([push_failure]) end)

      reject(&GitHubClient.redeliver_app_hook_delivery/1)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "redelivers the most recent attempt when multiple attempts exist for the same GUID" do
      # Two failed attempts for the same logical event; the newer
      # one is the right ID to redeliver from (GitHub re-fires that
      # delivery, with all its preserved request metadata).
      guid = "g-multi"
      older = delivery(id: 1, guid: guid, status_code: 502, delivered_at: ts_ago(600))
      newer = delivery(id: 2, guid: guid, status_code: 503, delivered_at: ts_ago(120), redelivery: true)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([newer, older]) end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id ->
        assert id == newer.id
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "paginates through delivery pages until the lookback boundary" do
      first_page_recent = delivery(id: 1, guid: "g-a", delivered_at: ts_ago(60))
      second_page_recent = delivery(id: 2, guid: "g-b", delivered_at: ts_ago(300))

      expect(GitHubClient, :list_app_hook_deliveries, 2, fn opts ->
        if Keyword.has_key?(opts, :next_url) do
          page([second_page_recent])
        else
          page([first_page_recent], next_url: "https://api.github.com/app/hook/deliveries?cursor=xyz")
        end
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, 2, fn _id -> :ok end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "stops paginating once a page contains entries older than the lookback window" do
      # Pages are newest-first; the moment we see a pre-threshold
      # delivery, no subsequent page can have anything newer than
      # the current threshold.
      recent = delivery(id: 1, guid: "g-recent", delivered_at: ts_ago(60))
      ancient = delivery(id: 2, guid: "g-ancient", delivered_at: ts_ago(15 * 60 + 30))

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts ->
        page([recent, ancient], next_url: "https://api.github.com/app/hook/deliveries?cursor=more")
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id ->
        assert id == recent.id
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "skips on transient GitHub list failure" do
      expect(GitHubClient, :list_app_hook_deliveries, fn _opts ->
        {:error, {:http, 502, "bad gateway"}}
      end)

      reject(&GitHubClient.redeliver_app_hook_delivery/1)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "treats a 422 from the redelivery endpoint as a transient skip, not a crash" do
      failed = delivery(id: 5_001)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([failed]) end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn _id ->
        {:error, {:http, 422, "Validation Failed"}}
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "emits recovery telemetry with kind=redelivered" do
      :telemetry.attach(
        "webhook-redelivery-test",
        Tuist.Runners.Telemetry.event_name_recovery(),
        fn _e, m, meta, _ -> send(self(), {:recovery, m, meta}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach("webhook-redelivery-test") end)

      failed = delivery(id: 8_001)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([failed]) end)
      expect(GitHubClient, :redeliver_app_hook_delivery, fn _id -> :ok end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})

      assert_received {:recovery, %{count: 1}, %{kind: "redelivered"}}
    end
  end

  defp ts_ago(seconds) do
    DateTime.add(DateTime.utc_now(), -seconds, :second)
  end
end
