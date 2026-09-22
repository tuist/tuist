defmodule Tuist.Runners.Workers.PruneVolumeMasterWorker do
  @moduledoc """
  Deletes a superseded runner cache-volume master object once its grace window
  has elapsed.

  The master object is content-addressed and immutable
  (`runner-volume-masters/<account>/<volume>/<master id>.image`), so a promote no
  longer overwrites the previous object — without this it would accumulate one
  multi-GB object per distinct inventory forever, cleaned only on account
  deletion. `Runners.report_volume_head/7` enqueues this with a delay equal to the
  presigned-URL TTL when a new digest supersedes an old one, so the object
  survives as long as any in-flight convergence could still fetch it.

  Best-effort: `Runners.prune_superseded_volume_master/3` re-checks the HEAD and
  skips the delete if the digest is (again) the current master. A transient
  storage error is retried across attempts; a persistent one just leaves the
  object for the account-deletion prefix cleanup.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Runners
  alias Tuist.Runners.VolumeHeads

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id} = args}) do
    master_id = master_id(args)

    case Runners.prune_superseded_volume_master(account_id, volume_name(args), master_id) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.warning(
          "runners: superseded volume master prune failed for #{account_id}/#{master_id}: #{inspect(reason)}"
        )

        error
    end
  end

  # Jobs enqueued before volumes were per repository name no volume.
  defp volume_name(%{"volume_name" => volume_name}), do: volume_name
  defp volume_name(_args), do: VolumeHeads.reserved_tuist_cache()

  # Jobs enqueued before master ids could carry a content digest name the object
  # by its inventory digest, which is still that object's id.
  defp master_id(%{"master_id" => master_id}), do: master_id
  defp master_id(%{"tree_digest" => tree_digest}), do: tree_digest
end
