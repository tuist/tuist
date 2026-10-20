defmodule Atlas.Repo.Migrations.AddDomainToPostmortems do
  use Ecto.Migration

  def change do
    alter table(:postmortems) do
      add :domain_id, references(:domains, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:postmortems, [:domain_id])
  end
end
