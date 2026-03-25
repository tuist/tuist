defmodule Cache.ProjectCleanupDiscoveryPollerTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Cache.ApplyProjectCleanupWorker
  alias Cache.DistributedKV.Cleanup
  alias Cache.ProjectCleanupDiscoveryPoller

  setup :set_mimic_from_context

  test "poll does not advance the discovery watermark when apply-job enqueue fails" do
    parent = self()
    current_watermark = 41
    next_watermark = 42
    cutoff = ~U[2026-03-12 12:00:00Z]

    invalid_changeset = ApplyProjectCleanupWorker.new(%{}, priority: 100)

    stub(Cleanup, :list_published_cleanups_after_event_id, fn ^current_watermark, 100 ->
      {[
         %{
           account_handle: "acme",
           project_handle: "ios",
           published_cleanup_generation: 7,
           published_cleanup_cutoff_at: cutoff,
           cleanup_event_id: next_watermark
         }
       ], next_watermark}
    end)

    stub(Cleanup, :put_local_discovery_watermark, fn watermark ->
      send(parent, {:watermark_advanced, watermark})
      :ok
    end)

    stub(ApplyProjectCleanupWorker, :new, fn _attrs -> invalid_changeset end)

    assert {:reply,
            {:error,
             %{
               account_handle: "acme",
               project_handle: "ios",
               changeset: changeset
             }},
            %{watermark: ^current_watermark}} =
             ProjectCleanupDiscoveryPoller.handle_call(:poll, self(), %{watermark: current_watermark})

    refute changeset.valid?
    assert changeset.errors == invalid_changeset.errors
    refute_received {:watermark_advanced, _}
  end
end
