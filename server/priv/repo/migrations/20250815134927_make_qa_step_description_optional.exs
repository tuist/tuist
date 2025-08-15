defmodule Tuist.Repo.Migrations.MakeQaStepDescriptionOptional do
  use Ecto.Migration

  def change do
    alter table(:qa_steps) do
      modify :description, :text, null: true
    end
  end
end
