defmodule Tuist.Repo.Migrations.EnforceOneOpenKuraDeploymentPerServer do
  use Ecto.Migration

  def up do
    # Keep an old server process from creating another open deployment between
    # the repair and the constraint becoming active. The table is operational
    # history and small enough that a brief write pause is safer than a
    # concurrent index whose build can race the version this deploy replaces.
    execute("LOCK TABLE kura_deployments IN SHARE ROW EXCLUSIVE MODE")

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

    create unique_index(:kura_deployments, [:kura_server_id],
             name: :kura_deployments_one_open_per_server_index,
             where: "status IN (0, 1)"
           )
  end

  def down do
    drop_if_exists index(:kura_deployments, [:kura_server_id],
                     name: :kura_deployments_one_open_per_server_index
                   )
  end
end
