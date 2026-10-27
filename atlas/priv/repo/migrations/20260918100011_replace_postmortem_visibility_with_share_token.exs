defmodule Atlas.Repo.Migrations.ReplacePostmortemVisibilityWithShareToken do
  use Ecto.Migration

  def change do
    drop_if_exists index(:postmortems, [:visibility, :inserted_at])

    alter table(:postmortems) do
      remove :visibility, :string, null: false, default: "public"
      add :share_token, :uuid
    end

    create unique_index(:postmortems, [:share_token])
  end
end
