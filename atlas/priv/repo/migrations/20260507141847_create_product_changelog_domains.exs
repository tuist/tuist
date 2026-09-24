defmodule Atlas.Repo.Migrations.CreateProductChangelogDomains do
  use Ecto.Migration

  def up do
    create table(:product_changelog_domains, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps()
    end

    create unique_index(:product_changelog_domains, ["lower(name)"],
             name: :product_changelog_domains_lower_name_index
           )

    flush()
    backfill_domains()
  end

  def down do
    drop table(:product_changelog_domains)
  end

  defp backfill_domains do
    %{rows: rows} =
      repo().query!(
        """
        SELECT DISTINCT trim(domain) AS name
        FROM product_changelog_entries, unnest(domains) AS domain
        WHERE trim(domain) != ''
        """,
        []
      )

    now = NaiveDateTime.utc_now(:second)

    domains =
      rows
      |> Enum.map(fn [name] -> name end)
      |> Enum.uniq_by(&String.downcase/1)
      |> Enum.map(fn name ->
        %{
          id: Ecto.UUID.dump!(Atlas.UUIDv7.generate()),
          name: name,
          inserted_at: now,
          updated_at: now
        }
      end)

    if domains != [] do
      repo().insert_all("product_changelog_domains", domains)
    end
  end
end
