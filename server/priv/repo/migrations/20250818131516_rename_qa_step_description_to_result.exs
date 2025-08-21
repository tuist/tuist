defmodule Tuist.Repo.Migrations.RenameQaStepDescriptionToResult do
  use Ecto.Migration

  def up do
    rename table(:qa_steps), :description, to: :result
  end

  def down do
    rename table(:qa_steps), :result, to: :description
  end
end
