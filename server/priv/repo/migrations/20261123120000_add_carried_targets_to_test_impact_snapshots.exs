defmodule Tuist.Repo.Migrations.AddCarriedTargetsToTestImpactSnapshots do
  @moduledoc """
  A checkpoint written from a selective run whose skips were all carried
  holds copies of the targets selective testing skipped by hash
  (`carried_targets`, each its name and hash joined by U+001F), so a later
  fold can carry a target from the copy once the snapshot it was measured in
  has expired. `evidence_measured_at` is when the oldest row it holds was
  measured: a copy is renewed with the checkpoint, so its evidence can be
  older than the checkpoint's run. It's null for every other snapshot, whose
  rows were all measured by its runs.
  """
  use Ecto.Migration

  def change do
    alter table(:test_impact_snapshots) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :carried_targets, {:array, :text}, null: false, default: []
      add :evidence_measured_at, :timestamptz
    end
  end
end
