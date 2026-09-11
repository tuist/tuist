defmodule Tuist.Repo.Migrations.AddNodeNameToRunnerSessions do
  use Ecto.Migration

  # Which host a job ran on was previously unrecoverable. The session records
  # pod_name, but the pod-to-node mapping lives only in Kubernetes as
  # Pod.spec.nodeName, and runner Pods are reaped when the job finishes. So a
  # completed job could never be attributed to a machine after the fact.
  #
  # That bites exactly when it matters most: during a fleet migration, comparing
  # the new hardware against the old is the question everyone asks, and it could
  # only be answered by snapshotting live pods on a timer and hoping to catch
  # them before they were reaped. Jobs that completed before someone started
  # watching were lost for good.
  #
  # Nullable with no backfill: rows written before this cannot be attributed,
  # and inventing a value for them would be worse than leaving the gap visible.
  # Dispatch already resolves the node for cache-volume affinity, so populating
  # it costs no extra Kubernetes call.
  def change do
    alter table(:runner_sessions) do
      add :node_name, :string
    end
  end
end
