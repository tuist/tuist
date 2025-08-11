defmodule Tuist.Repo.Migrations.AddIssueCommentIdToQARuns do
  use Ecto.Migration

  def change do
    alter table(:qa_runs) do
      add :issue_comment_id, :bigint
    end
  end
end
