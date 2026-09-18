defmodule Tuist.Runners.Workers.PruneVolumeMasterOrphanWorker do
  @moduledoc """
  Reclaims a rejected-promote cache-volume master object once its grace window
  has elapsed.

  The guest uploads the content-addressed `<master id>.image` before the
  fast-forward compare-and-swap, so a rejected promote leaves an object with no
  HEAD pointing at it (see `Tuist.Runners.VolumeMasterOrphans`).
  `Runners.report_volume_head/4` records the orphan and enqueues this with a
  delay equal to the presigned-URL TTL. `Runners.prune_orphan_volume_master/2`
  deletes the object only if the digest is still an orphan (never accepted as
  HEAD) and not the current HEAD, so a digest a later job committed is never
  reclaimed.

  Best-effort: a transient storage error is retried across attempts; a persistent
  one leaves the object for the account-deletion prefix cleanup.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Runners

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    master_id = master_id(args)

    case Runners.prune_orphan_volume_master(account_id, master_id) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.warning("runners: orphan volume master prune failed for #{account_id}/#{master_id}: #{inspect(reason)}")

        error
    end
  end

  # Jobs enqueued before master ids could carry a content digest name the object
  # by its inventory digest, which is still that object's id.
  defp master_id(%{"master_id" => master_id}), do: master_id
  defp master_id(%{"tree_digest" => tree_digest}), do: tree_digest
end
