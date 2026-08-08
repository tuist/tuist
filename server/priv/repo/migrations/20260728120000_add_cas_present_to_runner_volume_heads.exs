defmodule Tuist.Repo.Migrations.AddCasPresentToRunnerVolumeHeads do
  use Ecto.Migration

  # Whether the HEAD's image carries an Xcode compilation cache (CAS) store.
  #
  # It has to be stored rather than derived: `tree_digest` is a SHA-1 over the
  # inventory lines, so although those lines DO encode CAS presence (one `~cas/`
  # line per store file), the hash the server receives cannot be read back. The
  # promoting runner states it explicitly instead, and this column is what a
  # later promote is compared against.
  #
  # It exists because the fast-forward compare-and-swap only orders promotes by
  # GENERATION, never by content: a host that writes no CAS could publish a
  # CAS-less image as the account HEAD, and every other host would converge to it
  # and lose its compilation cache. `Tuist.Runners.VolumeHeads.bump_head/6`
  # refuses that unless the runner declares the drop intentional (an operator
  # turning the CAS off, which must stay promotable so the disable can propagate).
  #
  # Backfills to false, which leaves the guard inert until a runner promotes a
  # CAS-bearing image — so it can only ever start refusing on accounts where a
  # runner new enough to report CAS presence has already published one.
  def change do
    alter table(:runner_volume_heads) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :cas_present, :boolean, null: false, default: false
    end
  end
end
