defmodule Tuist.Repo.Migrations.CreateRunnerAssignments do
  use Ecto.Migration

  # State for the dispatch-time-bound runner pool. Each row is one
  # decision: "Pod <pod_uid> is bound to pool <pool_name> with this
  # GitHub JIT config." The Pod's startup script polls
  # /api/internal/runners/dispatch and the row is what the endpoint
  # returns. Postgres is the source of truth so we don't need
  # `pods/patch` RBAC on the runner namespace.
  def change do
    create table(:runner_assignments, primary_key: false) do
      # The Kubernetes Pod object's metadata.uid. Stable identifier
      # for the lifetime of the Pod, regenerated on Pod recreation.
      # Primary key so duplicate-dispatch attempts on the same Pod
      # error rather than silently reassigning.
      add :pod_uid, :string, primary_key: true, null: false

      # Pod's metadata.name. Convenient for `kubectl describe pod`
      # debugging without joining back to the API server.
      add :pod_name, :string, null: false

      # Pool the Pod was bound to. NULL = Pod is in the shared
      # warm pool, not yet dispatched to a customer. Matches the
      # `name` field in Tuist.Runners.PoolConfig once dispatched.
      add :pool_name, :string

      # GitHub JIT runner configuration — base64-encoded blob the
      # in-VM `./run.sh --jitconfig` consumes. Single-use, expires
      # ~1 h after issue if not registered. NULL until dispatch
      # binds the Pod to a customer; the row exists earlier (at
      # Pod-create time) so the dispatch token survives server
      # restarts between create and dispatch.
      add :jit_config, :text

      # The shared secret the Pod presents on dispatch. Random
      # 32-byte value generated at Pod-create time, stamped into the
      # Pod's env, and persisted here. Validates the dispatch caller
      # is in fact the Pod we minted the assignment for. Without
      # this anyone with network reach to the dispatch endpoint
      # could claim someone else's JIT config.
      add :dispatch_token_hash, :binary, null: false

      # When the dispatch endpoint returned the JIT to the VM. NULL
      # = not yet claimed. Set to NOW() on the first successful
      # dispatch read; subsequent reads return the same row
      # idempotently.
      add :claimed_at, :utc_datetime_usec

      # Audit fields, populated at dispatch time. NULL until the
      # Pod is bound to a customer pool.
      add :account_id, :integer
      add :owner, :string
      add :repo, :string

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_assignments, [:pool_name])
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_assignments, [:claimed_at])
  end
end
