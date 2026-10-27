defmodule Tuist.IngestRepo.Migrations.AddOriginToKuraUsageEvents do
  use Ecto.Migration

  # Where the credential behind a usage rollup was issued: an ISO 3166-1
  # country, narrowed to an ISO 3166-2 subdivision in the countries holding
  # more than one cache region. Empty for rollups whose credential carried none.
  def change do
    alter table(:kura_usage_events) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :origin, :"LowCardinality(String)", default: ""
    end
  end
end
