defmodule Tuist.Repo.Migrations.CleanupDuplicateSsoUserRoles do
  use Ecto.Migration

  def up do
    if Tuist.Environment.tuist_hosted?() do
      # PROBLEM: The original backfill migration created a cartesian product
      # SOLUTION: Just delete everything and use a single query to do it right

      # Delete all problematic roles
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute """
      DELETE FROM roles
      WHERE resource_type = 'Organization' AND name = 'user'
      AND created_at >= '2025-06-16 10:57:18'::timestamp
      AND created_at <= '2025-06-16 10:57:25'::timestamp;
      """

      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute """
      DELETE FROM users_roles
      WHERE created_at >= '2025-06-16 10:57:18'::timestamp
      AND created_at <= '2025-06-16 10:57:25'::timestamp
      """

      # Create one role per user per organization using a loop
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute """
      DO $$
      DECLARE
        user_rec RECORD;
        new_role_id BIGINT;
      BEGIN
        FOR user_rec IN
          SELECT DISTINCT
            u.id AS user_id,
            o.id AS organization_id
          FROM users u
          JOIN oauth2_identities oi ON oi.user_id = u.id
          JOIN organizations o ON o.sso_provider = oi.provider
                              AND o.sso_organization_id = oi.provider_organization_id
          WHERE NOT EXISTS (
            SELECT 1
            FROM users_roles ur
            JOIN roles r ON ur.role_id = r.id
            WHERE ur.user_id = u.id
              AND r.resource_type = 'Organization'
              AND r.resource_id = o.id
          )
        LOOP
          -- Insert a new role for this user-organization pair
          INSERT INTO roles (name, resource_type, resource_id, created_at, updated_at)
          VALUES ('user', 'Organization', user_rec.organization_id, NOW(), NOW())
          RETURNING id INTO new_role_id;

          -- Link the user to their new role
          INSERT INTO users_roles (user_id, role_id, created_at, updated_at)
          VALUES (user_rec.user_id, new_role_id, NOW(), NOW());
        END LOOP;
      END $$;
      """
    else
      :ok
    end
  end

  def down do
    # This cleanup cannot be safely reversed
    :ok
  end
end
