defmodule TuistOps.JIT.Workers.RevertWorkerTest do
  @moduledoc """
  RevertWorker is the freshness backstop: at TTL it flips the
  Elevation row to `reverted` so the policy endpoint stops
  returning the env-write group. The policy endpoint ALSO filters
  by `expires_at > now`, so a missed run can't keep an expired
  elevation alive — but the row-flip is what closes the Slack
  card and what shows up in audit queries.

  These tests pin the contract: row transitions correctly, the
  worker is idempotent on replay, and missing rows degrade
  gracefully (don't infinite-retry).
  """

  use TuistOps.DataCase, async: true
  use Mimic

  alias TuistOps.Repo
  alias TuistOps.JIT.Elevation
  alias TuistOps.JIT.Request
  alias TuistOps.JIT.SlackClient
  alias TuistOps.JIT.Workers.RevertWorker

  setup :verify_on_exit!

  setup do
    # Slack updates are best-effort; default to OK so tests focus
    # on the DB transition. Tests that care override.
    stub(SlackClient, :update_message, fn _, _, _ -> :ok end)
    :ok
  end

  defp insert_active_elevation!(opts \\ []) do
    expires_at =
      opts
      |> Keyword.get(:expires_at, DateTime.add(DateTime.utc_now(), 60, :second))
      |> DateTime.truncate(:second)

    request =
      %Request{
        requester_email: "marek@tuist.dev",
        requester_slack_id: "U_M",
        target_group: "group:tuist-staging-write",
        intent: "test",
        ttl_seconds: 60,
        slack_channel_id: "C_TEST",
        slack_message_ts: "1700000000.0001",
        expires_at: expires_at,
        status: "approved"
      }
      |> Repo.insert!()

    %Elevation{
      request_id: request.id,
      requester_email: request.requester_email,
      target_group: request.target_group,
      status: Keyword.get(opts, :status, "active"),
      expires_at: expires_at,
      reverted_at: Keyword.get(opts, :reverted_at)
    }
    |> Repo.insert!()
  end

  defp run_worker(elevation_id) do
    %Oban.Job{args: %{"elevation_id" => elevation_id}}
    |> RevertWorker.perform()
  end

  describe "perform/1" do
    test "active row → flips to reverted with reverted_at stamped" do
      elev = insert_active_elevation!()

      assert :ok = run_worker(elev.id)

      reloaded = Repo.get!(Elevation, elev.id)
      assert reloaded.status == "reverted"
      assert %DateTime{} = reloaded.reverted_at
    end

    test "already-reverted row → no-op, doesn't update reverted_at" do
      original_reverted_at = DateTime.truncate(~U[2024-01-01 00:00:00Z], :second)
      elev = insert_active_elevation!(status: "reverted", reverted_at: original_reverted_at)

      assert :ok = run_worker(elev.id)

      reloaded = Repo.get!(Elevation, elev.id)
      assert reloaded.status == "reverted"
      assert DateTime.compare(reloaded.reverted_at, original_reverted_at) == :eq
    end

    test "elevation row deleted out-of-band → returns :ok (avoids retry loop)" do
      # Integer PK; pick an id guaranteed not to collide.
      assert :ok = run_worker(999_999_999)
    end

    test "row past expires_at but still active → flips to reverted on the SAME perform" do
      # If RevertWorker's TTL-scheduled run fires after expires_at
      # (worker queue backlog), the row is still flipped — TTL
      # filtering is a defence-in-depth at the policy endpoint, not
      # something the worker checks before flipping.
      elev =
        insert_active_elevation!(expires_at: DateTime.add(DateTime.utc_now(), -10, :second))

      assert :ok = run_worker(elev.id)

      assert Repo.get!(Elevation, elev.id).status == "reverted"
    end

    test "updates the Slack approval card with a closed-state payload" do
      elev = insert_active_elevation!()

      expect(SlackClient, :update_message, fn channel, ts, blocks ->
        assert channel == "C_TEST"
        assert ts == "1700000000.0001"
        assert is_list(blocks) or is_map(blocks)
        :ok
      end)

      assert :ok = run_worker(elev.id)
    end

    test "Slack update failure does NOT fail the revert" do
      elev = insert_active_elevation!()

      stub(SlackClient, :update_message, fn _, _, _ -> {:error, :slack_down} end)

      # Must still succeed: the DB transition is authoritative;
      # Slack update is cosmetic.
      assert :ok = run_worker(elev.id)
      assert Repo.get!(Elevation, elev.id).status == "reverted"
    end
  end

  describe "Oban uniqueness" do
    test "queued under the elevation_id key in the :revert queue" do
      job = RevertWorker.new(%{"elevation_id" => "abc"})
      assert job.changes.queue == "revert"
      assert is_list(job.changes.unique[:fields])
      assert :args in job.changes.unique[:fields]
      assert :elevation_id in job.changes.unique[:keys]
    end
  end
end
