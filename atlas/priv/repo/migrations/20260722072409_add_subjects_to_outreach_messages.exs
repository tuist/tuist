defmodule Atlas.Repo.Migrations.AddSubjectsToOutreachMessages do
  use Ecto.Migration

  def change do
    alter table(:outreach_recommendations) do
      add :draft_subject, :string
    end

    alter table(:outreach_message_attempts) do
      add :proposed_subject, :string
      add :sent_subject, :string
    end
  end
end
