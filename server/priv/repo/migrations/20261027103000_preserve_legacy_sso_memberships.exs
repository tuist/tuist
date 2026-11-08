defmodule Tuist.Repo.Migrations.PreserveLegacySsoMemberships do
  use Ecto.Migration

  def up, do: preserve_memberships!(repo())

  # These are existing memberships, not grants that should disappear on rollback.
  def down, do: :ok

  def preserve_memberships!(repo) do
    repo.transaction(fn ->
      # Serialize the snapshot and inserts with role writes. No explicit role is changed.
      repo.query!("LOCK TABLE roles, users_roles IN SHARE ROW EXCLUSIVE MODE")

      repo.query!("""
      WITH members AS (
        SELECT DISTINCT oi.user_id, o.id AS organization_id,
               CASE WHEN o.sso_default_role = 'viewer' THEN 'viewer' ELSE 'user' END AS role_name
        FROM organizations o
        JOIN oauth2_identities oi
          ON oi.provider_organization_id = o.sso_organization_id
         AND oi.provider = CASE o.sso_provider WHEN 1 THEN 1 WHEN 3 THEN 4 END
        WHERE o.sso_provider IN (1, 3)
          AND o.sso_legacy_email_domain_fallback
          AND o.sso_automatic_enrollment
          AND NOT EXISTS (
            SELECT 1 FROM users_roles ur
            JOIN roles r ON r.id = ur.role_id
            WHERE ur.user_id = oi.user_id
              AND r.resource_type = 'Organization'
              AND r.resource_id = o.id
          )
      ), assignments AS MATERIALIZED (
        SELECT *, nextval(pg_get_serial_sequence('roles', 'id')) AS role_id FROM members
      ), inserted_roles AS (
        INSERT INTO roles (id, name, resource_type, resource_id, created_at, updated_at)
        SELECT role_id, role_name, 'Organization', organization_id, NOW(), NOW()
        FROM assignments
        RETURNING id
      )
      INSERT INTO users_roles (user_id, role_id, created_at, updated_at)
      SELECT a.user_id, a.role_id, NOW(), NOW()
      FROM assignments a JOIN inserted_roles r ON r.id = a.role_id
      """)
    end)

    :ok
  end
end
