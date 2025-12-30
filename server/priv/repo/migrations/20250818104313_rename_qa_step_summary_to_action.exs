defmodule Tuist.Repo.Migrations.RenameQaStepSummaryToAction do
  use Ecto.Migration

  def up do
    rename table(:qa_steps), :summary, to: :action
  end

  def down do
    rename table(:qa_steps), :action, to: :summary
  end
end
