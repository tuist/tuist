defmodule Tuist.Repo.Migrations.CreateCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    create table(:cache_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :url, :string, null: false
      add :display_name, :string, null: false
      add :environment, :string, null: false
      add :maintenance, :boolean, null: false, default: false

      timestamps(type: :timestamptz)
    end

    create unique_index(:cache_endpoints, [:url, :environment])
    create index(:cache_endpoints, [:environment])

    # Seed current hard-coded endpoints
    # Production (6 nodes)
    execute seed_sql("https://cache-eu-central.tuist.dev", "EU Central", "prod")
    execute seed_sql("https://cache-eu-north.tuist.dev", "EU North", "prod")
    execute seed_sql("https://cache-us-east.tuist.dev", "US East", "prod")
    execute seed_sql("https://cache-us-west.tuist.dev", "US West", "prod")
    execute seed_sql("https://cache-ap-southeast.tuist.dev", "Asia Pacific Southeast", "prod")
    execute seed_sql("https://cache-sa-west.tuist.dev", "South America West", "prod")

    # Staging (2 nodes)
    execute seed_sql("https://cache-eu-central-staging.tuist.dev", "EU Central Staging", "stag")
    execute seed_sql("https://cache-us-east-staging.tuist.dev", "US East Staging", "stag")

    # Canary (1 node)
    execute seed_sql("https://cache-eu-central-canary.tuist.dev", "EU Central Canary", "can")

    # Dev (1 node)
    execute seed_sql("http://localhost:8087", "Local Dev", "dev")

    # Test (2 nodes)
    execute seed_sql("https://cache-eu-central-test.tuist.dev", "EU Central Test", "test")
    execute seed_sql("https://cache-us-east-test.tuist.dev", "US East Test", "test")
  end

  def down do
    drop table(:cache_endpoints)
  end

  defp seed_sql(url, display_name, environment) do
    now =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    """
    INSERT INTO cache_endpoints (id, url, display_name, environment, maintenance, inserted_at, updated_at)
    VALUES (gen_random_uuid(), '#{url}', '#{display_name}', '#{environment}', false, '#{now}', '#{now}')
    """
  end
end
