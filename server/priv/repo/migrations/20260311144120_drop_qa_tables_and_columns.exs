defmodule Tuist.Repo.Migrations.DropQaTablesAndColumns do
  use Ecto.Migration

  def up do
    drop_if_exists table(:qa_screenshots)
    drop_if_exists table(:qa_recordings)
    drop_if_exists table(:qa_steps)
    drop_if_exists table(:qa_runs)
    drop_if_exists table(:qa_launch_argument_groups)

    alter table(:projects) do
      remove_if_exists :qa_app_description, :string
      remove_if_exists :qa_email, :string
      remove_if_exists :qa_password, :string
    end
  end

  def down do
    # QA feature has been removed; no rollback provided
    :ok
  end
end
