defmodule Tuist.Repo.Migrations.BackfillSsoUserRoles do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    WITH sso_users AS (
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
    )
    INSERT INTO roles (name, resource_type, resource_id, created_at, updated_at)
    SELECT 'user', 'Organization', organization_id, NOW(), NOW()
    FROM sso_users
    RETURNING id, resource_id, (SELECT user_id FROM sso_users WHERE sso_users.organization_id = roles.resource_id LIMIT 1) AS user_id;
    """

    # Safe: This query links the newly created roles to users based on
    # existing OAuth2 identities and organization SSO settings
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    WITH new_roles AS (
      SELECT DISTINCT
        u.id AS user_id,
        o.id AS organization_id,
        r.id AS role_id
      FROM users u
      JOIN oauth2_identities oi ON oi.user_id = u.id
      JOIN organizations o ON o.sso_provider = oi.provider
                          AND o.sso_organization_id = oi.provider_organization_id
      JOIN roles r ON r.resource_type = 'Organization'
                  AND r.resource_id = o.id
                  AND r.name = 'user'
      WHERE NOT EXISTS (
        SELECT 1
        FROM users_roles ur
        WHERE ur.user_id = u.id
          AND ur.role_id = r.id
      )
    )
    INSERT INTO users_roles (user_id, role_id, created_at, updated_at)
    SELECT user_id, role_id, NOW(), NOW()
    FROM new_roles;
    """
  end

  def down do
    :ok
  end
end
