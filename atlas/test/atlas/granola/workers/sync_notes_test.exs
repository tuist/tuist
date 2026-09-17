defmodule Atlas.Granola.Workers.SyncNotesTest do
  use ExUnit.Case, async: true

  alias Atlas.Granola.Workers.SyncNotes

  test "succeeds when Granola sync succeeds" do
    assert :ok =
             SyncNotes.perform(%Oban.Job{},
               sync_notes: fn opts ->
                 assert opts[:sync_mode] == :incremental
                 {:ok, %{captured: 1, ignored: 0}}
               end
             )
  end

  test "runs a backfill sync when requested" do
    assert :ok =
             SyncNotes.perform(%Oban.Job{args: %{"mode" => "backfill"}},
               sync_notes: fn opts ->
                 assert opts[:sync_mode] == :backfill
                 {:ok, %{captured: 1, ignored: 0}}
               end
             )
  end

  test "cancels when Granola sync is disabled" do
    assert {:cancel, :granola_sync_disabled} =
             SyncNotes.perform(%Oban.Job{}, sync_notes: fn -> :disabled end)
  end

  test "returns errors from Granola sync" do
    assert {:error, :timeout} =
             SyncNotes.perform(%Oban.Job{}, sync_notes: fn -> {:error, :timeout} end)
  end

  test "cancels on language model credit-limit failures" do
    reason = {:api_error, %{status: 402, body: %{"error" => "credit_limit"}}}

    assert {:cancel, :llm_credit_limit} =
             SyncNotes.perform(%Oban.Job{}, sync_notes: fn -> {:error, reason} end)
  end
end
