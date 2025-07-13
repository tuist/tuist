defmodule Tuist.Repo.Migrations.AddDeleteAllReferences do
  use Ecto.Migration

  def up do
    # users_last_visited_project_id_fkey
    drop constraint(:users, "fk_rails_cddfc1f87c")
    # device_codes_user_id_fkey
    drop constraint(:device_codes, "fk_rails_50c7f9f833")

    alter table(:command_events) do
      modify :project_id, references(:projects, on_delete: :delete_all)
    end

    alter table(:projects) do
      modify :account_id, references(:accounts, on_delete: :delete_all)
    end

    alter table(:users) do
      modify :last_visited_project_id, references(:projects, on_delete: :nilify_all)
    end

    alter table(:device_codes) do
      modify :user_id, references(:users, on_delete: :delete_all)
    end
  end

  def down do
    alter table(:command_events) do
      modify :project_id, references(:projects, on_delete: :nothing)
    end

    alter table(:projects) do
      modify :account_id, references(:accounts, on_delete: :nothing)
    end

    alter table(:users) do
      modify :last_visited_project_id, references(:projects, on_delete: :nothing)
    end

    alter table(:device_codes) do
      modify :user_id, references(:users, on_delete: :nothing)
    end

    drop constraint(:command_events, "command_events_project_id_fkey")
    drop constraint(:projects, "projects_account_id_fkey")
    drop constraint(:users, "users_last_visited_project_id_fkey")
    drop constraint(:device_codes, "device_codes_user_id_fkey")
  end
end
