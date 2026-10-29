defmodule Tuist.Repo.Migrations.RekeyRunnerClaimsByPodName do
  use Ecto.Migration

  # A claim is one of the account's concurrency slots, and a slot is held
  # by a Pod. GitHub binds a JIT runner to a label set and never to a
  # specific job, so the Pod minted for job A routinely runs job B. While
  # `workflow_job_id` was the primary key the claim could not outlive the
  # job it was minted for: freeing A meant deleting the row, and the row
  # is the Pod's slot. A displaced job therefore stayed unclaimable until
  # its Pod stopped.
  #
  # `pod_name` becomes the identity and `workflow_job_id` a nullable
  # attribute — which job this Pod is currently reserved for. Clearing it
  # returns the job to the queue without touching the slot.
  #
  # The atomic-claim primitive survives the move. `INSERT … ON CONFLICT DO
  # NOTHING` carries no conflict target, so it collapses on any unique
  # violation: the partial unique index below keeps "at most one live
  # claim per job" exactly as the primary key did, and the Pod primary key
  # keeps "at most one live claim per Pod".
  #
  # Every step runs inside the migration's transaction, which holds ACCESS
  # EXCLUSIVE on the table throughout, so no insert can slip between
  # dropping the primary key and creating the index that replaces its
  # uniqueness. The table holds only live claims (bounded by inflight
  # runners, tens of rows), so the lock is held for microseconds and the
  # dispatch path retries on the next poll.
  #
  # Replicas still on the previous release keep working against this shape:
  # they always write a `workflow_job_id`, their untargeted
  # `ON CONFLICT DO NOTHING` collapses on the new constraints, and none of
  # them fetches a claim by primary key. The one thing they cannot read is
  # a NULL `workflow_job_id`, which a new replica starts writing on the
  # first displaced job. For the length of the rollout that costs an old
  # replica a `count(workflow_job_id)` per fleet (the autoscaler takes the
  # Pod-counted `occupied_counts_per_fleet/0` over it anyway) and one
  # `PodReconciliationWorker` tick if a claim it cannot key reaches the
  # release pass — the next tick, on a new replica, releases it.
  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE runner_claims DROP CONSTRAINT runner_claims_pkey")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE runner_claims ALTER COLUMN workflow_job_id DROP NOT NULL")

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_claims, [:workflow_job_id],
             where: "workflow_job_id IS NOT NULL",
             name: :runner_claims_workflow_job_id_unique_index
           )

    # Promotes the index `MakeRunnerClaimPodNameUnique` already built
    # instead of scanning the table again. Postgres renames it to the
    # constraint name, so `runner_claims_pod_name_unique_index` is gone
    # after this and the primary key carries the uniqueness.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE runner_claims ADD CONSTRAINT runner_claims_pkey PRIMARY KEY USING INDEX runner_claims_pod_name_unique_index"
    )
  end

  def down do
    # A claim whose job was cleared has no key under the old shape. Rolling
    # back drops it, which frees a slot its Pod may still be using; the
    # alternative is a rollback that cannot run at all. The Pod-stop report
    # and `PodReconciliationWorker` re-converge the account's count.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("DELETE FROM runner_claims WHERE workflow_job_id IS NULL")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE runner_claims DROP CONSTRAINT runner_claims_pkey")

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_claims, [:pod_name], name: :runner_claims_pod_name_unique_index)

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop index(:runner_claims, [:workflow_job_id],
           name: :runner_claims_workflow_job_id_unique_index
         )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("ALTER TABLE runner_claims ALTER COLUMN workflow_job_id SET NOT NULL")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      "ALTER TABLE runner_claims ADD CONSTRAINT runner_claims_pkey PRIMARY KEY (workflow_job_id)"
    )
  end
end
