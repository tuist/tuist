defmodule Tuist.Repo.Migrations.ChangeQaStepIssuesType do
  use Ecto.Migration

  def up do
    alter table(:qa_steps) do
      modify :issues, {:array, :text}, null: false
    end
  end

  def down do
    alter table(:qa_steps) do
      modify :issues, {:array, :string}, null: false
    end
  end
end
