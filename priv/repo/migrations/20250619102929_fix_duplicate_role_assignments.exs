defmodule Tuist.Repo.Migrations.FixDuplicateRoleAssignments do
  use Ecto.Migration

  def up do
    # Fix duplicate role assignments where multiple users are connected to the same role
    # Each user should have their own unique role per organization
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    DO $$
    DECLARE
      duplicate_role RECORD;
      user_role_rec RECORD;
      first_user_id INTEGER;
      new_role_id BIGINT;
      role_info RECORD;
    BEGIN
      -- Process each role that has duplicate assignments
      FOR duplicate_role IN
        SELECT role_id, COUNT(*) as duplicate_count
        FROM users_roles
        GROUP BY role_id
        HAVING COUNT(*) > 1
      LOOP
        -- Get the role information for creating new roles
        SELECT name, resource_type, resource_id
        INTO role_info
        FROM roles
        WHERE id = duplicate_role.role_id;

        -- Get the first user (chronologically) to keep with the original role
        SELECT user_id
        INTO first_user_id
        FROM users_roles
        WHERE role_id = duplicate_role.role_id
        ORDER BY created_at ASC
        LIMIT 1;

        -- For each additional user, create a new role and update their assignment
        FOR user_role_rec IN
          SELECT user_id, created_at, updated_at
          FROM users_roles
          WHERE role_id = duplicate_role.role_id
            AND user_id != first_user_id
          ORDER BY created_at ASC
        LOOP
          -- Create a new role for this user
          INSERT INTO roles (name, resource_type, resource_id, created_at, updated_at)
          VALUES (role_info.name, role_info.resource_type, role_info.resource_id, NOW(), NOW())
          RETURNING id INTO new_role_id;

          -- Update the users_roles entry to point to the new role
          UPDATE users_roles
          SET role_id = new_role_id,
              updated_at = NOW()
          WHERE role_id = duplicate_role.role_id
            AND user_id = user_role_rec.user_id;
        END LOOP;
      END LOOP;
    END $$;
    """
  end

  def down do
    # This migration cannot be safely reversed as it would require
    # recreating the duplicate state which was the original problem
    :ok
  end
end
