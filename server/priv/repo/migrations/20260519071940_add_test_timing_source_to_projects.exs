defmodule Tuist.Repo.Migrations.AddTestTimingSourceToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :test_timing_source, :integer, default: 0, null: false
      add :test_timing_branch, :string
    end
  end
end
