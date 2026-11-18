defmodule Tuist.Repo.Migrations.AddEntireTrailReportCommentPointers do
  use Ecto.Migration

  def change do
    alter table(:entire_trail_reports) do
      add :discussion_id, :string
      add :message_id, :string
    end
  end
end
