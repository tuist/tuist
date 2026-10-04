defmodule Tuist.Repo.Migrations.AddHeadObservedAtToGitRefs do
  @moduledoc """
  When the observation that last moved a ref was made: a run's time for a
  fold, the client's for a branch head it saw. An older observation leaves
  the ref where it is, so a late report of a commit a force-push rewrote, or
  a refold of an old commit, cannot move the ref back
  (`Tuist.GitHistory.advance_ref/5`).
  """
  use Ecto.Migration

  def change do
    alter table(:git_refs) do
      add :head_observed_at, :timestamptz
    end
  end
end
