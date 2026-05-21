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

  defp global_app do
    %{
      credentials: %{
        app_name: "tuist",
        app_id: "global-app",
        client_id: "cid",
        client_secret: "cs",
        private_key: "pk",
        webhook_secret: "ws"
      },
      api_url: "https://api.github.com"
    }
  end

  defp ghes_app do
    %{
      credentials: %{
        app_name: "tuist-ghes",
        app_id: "ghes-app",
        client_id: "cid",
        client_secret: "cs",
        private_key: "pk",
        webhook_secret: "ws"
      },
      api_url: "https://ghes.example.com/api/v3"
    }
  end

  describe "perform/1" do
    test "is a no-op when GitHub reports no deliveries" do
      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)
      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([]) end)
      reject(&GitHubClient.redeliver_app_hook_delivery/2)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "asks GitHub to redeliver a failed workflow_job delivery" do
      failed = delivery(id: 7_001, guid: "g-1", status_code: 500)

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)

      expect(GitHubClient, :list_app_hook_deliveries, fn opts ->
        # No status filter — GitHub's `?status=failure` would hide
        # the successful redelivery attempts we need to see for
        # dedup. Verify we're not requesting it.
        refute Keyword.has_key?(opts, :status)
        page([failed])
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id, opts ->
        assert id == failed.id
        assert Keyword.get(opts, :api_url) == "https://api.github.com"
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "skips a GUID whose attempts include any successful one" do
      # GitHub's documented dedup: the original failure AND the
      # successful redelivery share a GUID. The successful one is
      # included in the list response (we don't filter to failures
      # server-side) so the dedup check sees it and skips.
      guid = "g-dedup"

      original_failure = delivery(id: 1, guid: guid, status_code: 500, delivered_at: ts_ago(300))

      successful_redelivery =
        delivery(id: 2, guid: guid, status_code: 200, status: "OK", redelivery: true, delivered_at: ts_ago(60))

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts ->
        page([successful_redelivery, original_failure])
      end)

      reject(&GitHubClient.redeliver_app_hook_delivery/2)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "skips deliveries that are not workflow_job events" do
      push_failure = delivery(id: 9_001, guid: "g-push", event: "push", action: nil)

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)
      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([push_failure]) end)
      reject(&GitHubClient.redeliver_app_hook_delivery/2)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "redelivers the most recent attempt when multiple attempts exist for the same GUID" do
      guid = "g-multi"
      older = delivery(id: 1, guid: guid, status_code: 502, delivered_at: ts_ago(600))
      newer = delivery(id: 2, guid: guid, status_code: 503, delivered_at: ts_ago(120), redelivery: true)

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)
      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([newer, older]) end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id, _opts ->
        assert id == newer.id
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "paginates through delivery pages until the lookback boundary" do
      first_page_recent = delivery(id: 1, guid: "g-a", delivered_at: ts_ago(60))
      second_page_recent = delivery(id: 2, guid: "g-b", delivered_at: ts_ago(300))

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)

      expect(GitHubClient, :list_app_hook_deliveries, 2, fn opts ->
        if Keyword.has_key?(opts, :next_url) do
          page([second_page_recent])
        else
          page([first_page_recent], next_url: "https://api.github.com/app/hook/deliveries?cursor=xyz")
        end
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, 2, fn _id, _opts -> :ok end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "stops paginating once a page contains entries older than the lookback window" do
      recent = delivery(id: 1, guid: "g-recent", delivered_at: ts_ago(60))
      ancient = delivery(id: 2, guid: "g-ancient", delivered_at: ts_ago(15 * 60 + 30))

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts ->
        page([recent, ancient], next_url: "https://api.github.com/app/hook/deliveries?cursor=more")
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id, _opts ->
        assert id == recent.id
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "iterates each App's delivery log independently (github.com + GHES manifest-flow Apps)" do
      # The crux of the GHES fix: a per-installation manifest-flow
      # App on GHES has its own webhook delivery log under its own
      # api_url. The worker must query each App's log with the
      # right credentials and api_url.
      global = global_app()
      ghes = ghes_app()

      global_failure = delivery(id: 1_001, guid: "g-global", installation_id: 100)
      ghes_failure = delivery(id: 2_002, guid: "g-ghes", installation_id: 200)

      expect(Tuist.VCS, :list_github_apps, fn -> [global, ghes] end)

      expect(GitHubClient, :list_app_hook_deliveries, 2, fn opts ->
        case Keyword.get(opts, :api_url) do
          "https://api.github.com" ->
            assert Keyword.get(opts, :credentials) == global.credentials
            page([global_failure])

          "https://ghes.example.com/api/v3" ->
            assert Keyword.get(opts, :credentials) == ghes.credentials
            page([ghes_failure])
        end
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, 2, fn id, opts ->
        case id do
          1_001 ->
            assert Keyword.get(opts, :api_url) == "https://api.github.com"
            assert Keyword.get(opts, :credentials) == global.credentials

          2_002 ->
            assert Keyword.get(opts, :api_url) == "https://ghes.example.com/api/v3"
            assert Keyword.get(opts, :credentials) == ghes.credentials
        end

        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "continues to other Apps when one App's list call fails" do
      # Per-App isolation: a GHES instance being unreachable must
      # not stall recovery for the github.com App.
      global = global_app()
      ghes = ghes_app()

      ghes_failure = delivery(id: 2_002, guid: "g-ghes")

      expect(Tuist.VCS, :list_github_apps, fn -> [global, ghes] end)

      expect(GitHubClient, :list_app_hook_deliveries, 2, fn opts ->
        case Keyword.get(opts, :api_url) do
          "https://api.github.com" -> {:error, {:transport, :timeout}}
          "https://ghes.example.com/api/v3" -> page([ghes_failure])
        end
      end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn id, _opts ->
        assert id == ghes_failure.id
        :ok
      end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "skips on transient GitHub list failure for the only App" do
      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)

      expect(GitHubClient, :list_app_hook_deliveries, fn _opts ->
        {:error, {:http, 502, "bad gateway"}}
      end)

      reject(&GitHubClient.redeliver_app_hook_delivery/2)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})
    end

    test "treats a 422 from the redelivery endpoint as a transient skip, not a crash" do
      failed = delivery(id: 5_001)

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)
      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([failed]) end)

      expect(GitHubClient, :redeliver_app_hook_delivery, fn _id, _opts ->
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

      expect(Tuist.VCS, :list_github_apps, fn -> [global_app()] end)
      expect(GitHubClient, :list_app_hook_deliveries, fn _opts -> page([failed]) end)
      expect(GitHubClient, :redeliver_app_hook_delivery, fn _id, _opts -> :ok end)

      assert :ok = WebhookRedeliveryWorker.perform(%Oban.Job{})

      assert_received {:recovery, %{count: 1}, %{kind: "redelivered"}}
    end
  end

  defp ts_ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)
end
