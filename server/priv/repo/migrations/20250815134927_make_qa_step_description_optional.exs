defmodule Tuist.Repo.Migrations.MakeQaStepDescriptionOptional do
  use Ecto.Migration

  def up do
    alter table(:qa_steps) do
      modify :description, :text, null: true
    end
  end

  def down do
    alter table(:qa_steps) do
      modify :description, :text, null: false
    end
  end
end
