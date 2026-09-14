defmodule Tuist.Repo.Migrations.CreateKuraPlacerRegions do
  use Ecto.Migration

  # Where the placer decided an account is served from, and the reason
  # placement is no longer an accident of the resolution defaults. A primary
  # row is the account's service region; secondary rows are the additional
  # regions sustained demand justified.
  #
  # Separate from `kura_account_region_policies`, which stays what it is: an
  # operator's explicit assignment, made by a named person, that takes an
  # account out of the placer's hands entirely. Writing placer output there
  # would make every account the placer touched look pinned, and pinning is
  # the rollback.
  def change do
    create table(:kura_placer_regions) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :region, :string, null: false
      add :role, :string, null: false, default: "primary"
      # A region kept in resolution while its instance drains, so nothing
      # re-provisions behind a retirement that is still finishing.
      add :status, :string, null: false, default: "desired"
      add :evidence, :map, null: false, default: %{}

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so building its unique indexes inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_placer_regions, [:account_id, :region])

    # One primary per account: resolution answers with a single region, and two
    # primaries would make which one it answers with depend on row order.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_placer_regions, [:account_id],
             where: "role = 'primary'",
             name: :kura_placer_regions_one_primary_per_account
           )
  end
end
