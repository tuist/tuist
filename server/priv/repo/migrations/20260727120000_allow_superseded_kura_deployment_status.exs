defmodule Tuist.Repo.Migrations.AllowSupersededKuraDeploymentStatus do
  use Ecto.Migration

  def up do
    drop constraint(:kura_deployments, :kura_deployments_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_deployments, :kura_deployments_status_valid,
             check: "status IN (0, 1, 2, 3, 4, 5)"
           )
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute("""
    UPDATE kura_deployments
    SET status = 4,
        error_message = COALESCE(error_message, 'cancelled while rolling back superseded deployment support'),
        finished_at = COALESCE(finished_at, NOW()),
        updated_at = NOW()
    WHERE status = 5
    """)

    drop constraint(:kura_deployments, :kura_deployments_status_valid)

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_deployments, :kura_deployments_status_valid,
             check: "status IN (0, 1, 2, 3, 4)"
           )
  end
end
