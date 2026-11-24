defmodule Tuist.Repo.Migrations.ChangeRunnerWorkflowNamesToText do
  use Ecto.Migration

  # GitHub copies a run's `run-name` into `workflow_job.workflow_name`, and a
  # run name built from a pull request title and commit message can exceed
  # 255 characters, as can matrix job names and branch names. Webhook inserts
  # then failed with `string_data_right_truncation`. Postgres changes
  # `varchar` to `text` without rewriting the table or its indexes.
  def up do
    alter table(:runner_workflow_jobs) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :workflow_name, :text, from: :string
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :job_name, :text, from: :string
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :head_branch, :text, from: :string
    end

    alter table(:runner_sessions) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :workflow_name, :text, from: :string
    end
  end

  # Fails once a row holds a value longer than 255 characters.
  def down do
    alter table(:runner_workflow_jobs) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :workflow_name, :string, from: :text
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :job_name, :string, from: :text
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :head_branch, :string, from: :text
    end

    alter table(:runner_sessions) do
      # excellent_migrations:safety-assured-for-next-line column_type_changed
      modify :workflow_name, :string, from: :text
    end
  end
end
