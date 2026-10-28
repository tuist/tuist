defmodule Atlas.Repo.Migrations.MakePostmortemDomainsManyToMany do
  use Ecto.Migration

  def up do
    create table(:domains_postmortems, primary_key: false) do
      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all), null: false

      add :postmortem_id, references(:postmortems, type: :binary_id, on_delete: :delete_all),
        null: false
    end

    create unique_index(:domains_postmortems, [:domain_id, :postmortem_id])

    execute """
    INSERT INTO domains_postmortems (domain_id, postmortem_id)
    SELECT domain_id, id FROM postmortems WHERE domain_id IS NOT NULL
    """

    alter table(:postmortems) do
      remove :domain_id
    end
  end

  def down do
    alter table(:postmortems) do
      add :domain_id, references(:domains, type: :binary_id, on_delete: :nilify_all)
    end

    execute """
    UPDATE postmortems SET domain_id = domains_postmortems.domain_id
    FROM domains_postmortems WHERE domains_postmortems.postmortem_id = postmortems.id
    """

    drop_if_exists unique_index(:domains_postmortems, [:domain_id, :postmortem_id])
    drop table(:domains_postmortems)
  end
end
