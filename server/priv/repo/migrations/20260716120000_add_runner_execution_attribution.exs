defmodule Tuist.Repo.Migrations.AddRunnerExecutionAttribution do
  use Ecto.Migration

  # `executed_workflow_job_id` records which workflow_job a runner
  # actually ran, as reported by GitHub.
  #
  # A runner is minted with a name we choose and registered with the
  # pool's shared labels. GitHub assigns queued jobs to any
  # label-eligible runner independently of which `workflow_job_id`
  # the server claimed, so the runner minted "for" job X frequently
  # runs a different job (or none). The claim/session rows record the
  # CLAIMED job; the only ground truth for the EXECUTED job is the
  # `runner_name` carried on the `workflow_job.in_progress` /
  # `completed` webhooks.
  #
  # `executed_workflow_job_id` holds that proven binding once a
  # webhook names the runner. It stays NULL until GitHub proves the
  # runner ran something — the absence of a value is exactly the
  # "idle / never assigned work" signal. `runner_name` gets an index
  # on both tables so the webhook handler can resolve
  # `runner_name → row` cheaply (the mint-chosen name is unique per
  # runner and already stored on both rows).
  def change do
    alter table(:runner_claims) do
      add :executed_workflow_job_id, :bigint
    end

    alter table(:runner_sessions) do
      add :executed_workflow_job_id, :bigint
    end

    # Webhook attribution resolves the live claim by the GitHub-reported
    # runner_name.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:runner_name])

    # Durable attribution backstop: the session outlives the pod, so a
    # `completed` webhook can still bind the runner after a fast job's pod
    # is gone. Deliberately NOT partial on `runner_name <> ''`: the lookup
    # is parameterized equality through Ecto's prepared statements, and
    # Postgres cannot prove `$1 <> ''` when building a generic plan, so a
    # partial index is invisible to it — on an append-only table that grows
    # forever, this is the hottest new query path. Partiality would also
    # exclude almost nothing, since every session gets a real runner_name
    # at open.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_sessions, [:runner_name])
  end
end
