defmodule Tuist.Repo.Migrations.MakeRunnerClaimPodNameUnique do
  use Ecto.Migration

  def up do
    # `runner_claims` contains only live claims and is bounded by runner
    # capacity, so building this index synchronously touches a small table.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_claims, [:pod_name], name: :runner_claims_pod_name_unique_index)

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop index(:runner_claims, [:pod_name], name: :runner_claims_pod_name_index)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:pod_name], name: :runner_claims_pod_name_index)

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop index(:runner_claims, [:pod_name], name: :runner_claims_pod_name_unique_index)
  end
end
