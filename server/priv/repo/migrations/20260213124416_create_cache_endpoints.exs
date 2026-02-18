defmodule Tuist.Repo.Migrations.CreateCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  def up do
    create table(:cache_endpoints, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :url, :string, null: false
      add :display_name, :string, null: false
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :timestamptz)
    end

    create unique_index(:cache_endpoints, [:url])

    if Tuist.Environment.tuist_hosted?() do
      seed_endpoints_for_environment(Tuist.Environment.env())
    end
  end

  def down do
    drop table(:cache_endpoints)
  end

  defp seed_endpoints_for_environment(:prod) do
    execute seed_sql("https://cache-eu-central.tuist.dev", "EU Central")
    execute seed_sql("https://cache-eu-north.tuist.dev", "EU North")
    execute seed_sql("https://cache-us-east.tuist.dev", "US East")
    execute seed_sql("https://cache-us-west.tuist.dev", "US West")
    execute seed_sql("https://cache-ap-southeast.tuist.dev", "Asia Pacific Southeast")
    execute seed_sql("https://cache-sa-west.tuist.dev", "South America West")
  end

  defp seed_endpoints_for_environment(:stag) do
    execute seed_sql("https://cache-eu-central-staging.tuist.dev", "EU Central Staging")
    execute seed_sql("https://cache-us-east-staging.tuist.dev", "US East Staging")
  end

  defp seed_endpoints_for_environment(:can) do
    execute seed_sql("https://cache-eu-central-canary.tuist.dev", "EU Central Canary")
  end

  defp seed_endpoints_for_environment(:dev) do
    execute seed_sql("http://localhost:8087", "Local Dev")
  end

  defp seed_endpoints_for_environment(:test) do
    execute seed_sql("https://cache-eu-central-test.tuist.dev", "EU Central Test")
    execute seed_sql("https://cache-us-east-test.tuist.dev", "US East Test")
  end

  defp seed_endpoints_for_environment(_), do: :ok

  defp seed_sql(url, display_name) do
    now =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    """
    INSERT INTO cache_endpoints (id, url, display_name, enabled, inserted_at, updated_at)
    VALUES (gen_random_uuid(), '#{url}', '#{display_name}', true, '#{now}', '#{now}')
    """
  end
end
