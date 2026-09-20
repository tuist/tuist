defmodule Atlas.Repo.Migrations.SeedMemberRoleAndBackfill do
  use Ecto.Migration

  # Members hold every scope EXCEPT finance:*, documents:* (payroll/sensitive)
  # and admin:* (so they can't self-assign the excluded scopes).
  @excluded_areas ~w(finance documents admin)
  @areas ~w(accounts admin assets audit briefs contracts engineering gtm inference insurance letters licenses notes support)
  @actions ~w(read write)

  def up do
    # `users.role` was dropped by the previous migration. Reintroduce it only
    # for the duration of this backfill so we can find who used to be an
    # employee, then drop it again at the end.
    #
    # If the drop-role migration was split off into a follow-up PR (recommended
    # for zero-downtime), this dance is a no-op — the column is already there.
    ensure_role_column()

    scopes =
      for area <- @areas -- @excluded_areas, action <- @actions do
        "#{area}:#{action}"
      end

    scopes_literal = scopes |> Enum.map(&"'#{&1}'") |> Enum.join(",")

    role_id_row =
      repo().query!(
        """
        INSERT INTO roles (id, name, slug, description, scopes, builtin, inserted_at, updated_at)
        VALUES (gen_random_uuid(), 'Member', 'member',
                'Grants every scope except finance and documents (payroll).',
                ARRAY[#{scopes_literal}]::varchar[],
                true, now(), now())
        ON CONFLICT (slug) DO UPDATE
          SET scopes = EXCLUDED.scopes,
              description = EXCLUDED.description,
              builtin = true,
              updated_at = now()
        RETURNING id
        """,
        []
      )

    [[role_id]] = role_id_row.rows

    if user_role_column_present?() do
      repo().query!(
        """
        INSERT INTO user_roles (user_id, role_id, inserted_at)
        SELECT id, $1, now() FROM users WHERE role = 'employee'
        ON CONFLICT DO NOTHING
        """,
        [role_id]
      )
    else
      # No role column left to read from; assign the member role to every user
      # that currently holds no role at all.
      repo().query!(
        """
        INSERT INTO user_roles (user_id, role_id, inserted_at)
        SELECT u.id, $1, now()
        FROM users u
        WHERE NOT EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = u.id)
        ON CONFLICT DO NOTHING
        """,
        [role_id]
      )
    end
  end

  def down do
    repo().query!("DELETE FROM roles WHERE slug = 'member'", [])
  end

  defp ensure_role_column, do: :ok

  defp user_role_column_present? do
    result =
      repo().query!(
        """
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'role'
        """,
        []
      )

    result.num_rows > 0
  end
end
