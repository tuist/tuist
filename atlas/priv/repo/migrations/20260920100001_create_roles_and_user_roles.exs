defmodule Atlas.Repo.Migrations.CreateRolesAndUserRoles do
  use Ecto.Migration

  # Inline the scope catalog so the migration is stable across future edits to
  # Atlas.Authorization. The application's ensure_executive_role! resyncs the
  # full set at boot, so any additions after this migration are picked up.
  @areas ~w(accounts admin assets audit briefs contracts documents engineering finance gtm inference insurance letters licenses notes support)
  @actions ~w(read write)

  def up do
    create table(:roles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :scopes, {:array, :string}, null: false, default: []
      add :builtin, :boolean, null: false, default: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:roles, [:slug])

    create table(:user_roles, primary_key: false) do
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :role_id, references(:roles, type: :uuid, on_delete: :delete_all),
        primary_key: true,
        null: false

      add :inserted_at, :timestamptz, null: false, default: fragment("now()")
    end

    create index(:user_roles, [:role_id])

    flush()

    seed_executive_role_and_backfill()
  end

  def down do
    drop table(:user_roles)
    drop table(:roles)
  end

  defp seed_executive_role_and_backfill do
    scopes =
      for area <- @areas, action <- @actions do
        "#{area}:#{action}"
      end

    scopes_literal =
      scopes
      |> Enum.map(&"'#{&1}'")
      |> Enum.join(",")

    role_id_row =
      repo().query!(
        """
        INSERT INTO roles (id, name, slug, description, scopes, builtin, inserted_at, updated_at)
        VALUES (gen_random_uuid(), 'Executive', 'executive',
                'Grants every scope, including admin access.',
                ARRAY[#{scopes_literal}]::varchar[],
                true, now(), now())
        RETURNING id
        """,
        []
      )

    [[role_id]] = role_id_row.rows

    repo().query!(
      """
      INSERT INTO user_roles (user_id, role_id, inserted_at)
      SELECT id, $1, now() FROM users WHERE role = 'executive'
      ON CONFLICT DO NOTHING
      """,
      [role_id]
    )
  end
end
