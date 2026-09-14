defmodule Tuist.Repo.Migrations.CreateKuraPlacerClaims do
  use Ecto.Migration

  # The claim automatic sizing chose for an account, sitting between the
  # operator override (which wins, and hides the account from sizing entirely)
  # and the plan constant (which becomes the starting value rather than the
  # size). A separate table from kura_storage_claims so clearing an operator
  # override falls back to the sized claim instead of snapping to the plan,
  # and so an operator row keeps meaning "a human decided this".
  def change do
    create table(:kura_placer_claims) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :claim_size, :string, null: false

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_placer_claims, [:account_id])
  end
end
