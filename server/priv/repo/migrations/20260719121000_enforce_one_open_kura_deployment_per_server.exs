defmodule Tuist.Repo.Migrations.EnforceOneOpenKuraDeploymentPerServer do
  use Ecto.Migration

  def up do
    # Keep an old server process from creating another open deployment between
    # the repair and the constraint becoming active. The table is operational
    # history and small enough that a brief write pause is safer than a
    # concurrent index whose build can race the version this deploy replaces.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    execute("LOCK TABLE kura_deployments IN SHARE ROW EXCLUSIVE MODE")

    # The ranking query cannot be expressed through the migration helpers.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    execute("""
    WITH ranked AS (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY kura_server_id
               ORDER BY inserted_at DESC, id DESC
             ) AS position
      FROM kura_deployments
      WHERE status IN (0, 1)
    )
    UPDATE kura_deployments AS deployment
    SET status = 4,
        error_message = 'cancelled while enforcing one open deployment per Kura server',
        finished_at = NOW(),
        updated_at = NOW()
    FROM ranked
    WHERE deployment.id = ranked.id
      AND ranked.position > 1
    """)

    # The index must be created while the transaction still owns the table lock.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    create unique_index(:kura_deployments, [:kura_server_id],
             name: :kura_deployments_one_open_per_server_index,
             where: "status IN (0, 1)"
           )
  end

  def down do
    # Keep the rollback in the same transaction as the rest of this migration.
    # credo:disable-for-next-line ExcellentMigrations.CredoCheck.MigrationsSafety
    drop_if_exists index(:kura_deployments, [:kura_server_id],
                     name: :kura_deployments_one_open_per_server_index
                   )
  end
end
