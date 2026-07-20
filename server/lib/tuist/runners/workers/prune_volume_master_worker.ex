defmodule Tuist.Runners.Workers.PruneVolumeMasterWorker do
  @moduledoc """
  Deletes a superseded runner cache-volume master object once its grace window
  has elapsed.

  The master object is content-addressed and immutable
  (`runner-volume-masters/<account>/tuist-cache/<digest>.image`), so a promote no
  longer overwrites the previous object — without this it would accumulate one
  multi-GB object per distinct inventory forever, cleaned only on account
  deletion. `Runners.report_volume_head/3` enqueues this with a delay equal to the
  presigned-URL TTL when a new digest supersedes an old one, so the object
  survives as long as any in-flight convergence could still fetch it.

  Best-effort: `Runners.prune_superseded_volume_master/2` re-checks the HEAD and
  skips the delete if the digest is (again) the current master. A transient
  storage error is retried across attempts; a persistent one just leaves the
  object for the account-deletion prefix cleanup.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Runners

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "tree_digest" => tree_digest}}) do
    case Runners.prune_superseded_volume_master(account_id, tree_digest) do
      :ok ->
        :ok

      {:error, reason} = error ->
        Logger.warning(
          "runners: superseded volume master prune failed for #{account_id}/#{tree_digest}: #{inspect(reason)}"
        )

        error
    end
  end
end
