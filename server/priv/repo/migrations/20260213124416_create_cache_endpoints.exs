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

  defp seed_endpoints_for_environment(env) do
    case env do
      :prod ->
        execute seed_sql("https://cache-eu-central.tuist.dev", "EU Central")
        execute seed_sql("https://cache-eu-north.tuist.dev", "EU North")
        execute seed_sql("https://cache-us-east.tuist.dev", "US East")
        execute seed_sql("https://cache-us-west.tuist.dev", "US West")
        execute seed_sql("https://cache-ap-southeast.tuist.dev", "Asia Pacific Southeast")
        execute seed_sql("https://cache-sa-west.tuist.dev", "South America West")

      :stag ->
        execute seed_sql("https://cache-eu-central-staging.tuist.dev", "EU Central Staging")
        execute seed_sql("https://cache-us-east-staging.tuist.dev", "US East Staging")

      :can ->
        execute seed_sql("https://cache-eu-central-canary.tuist.dev", "EU Central Canary")

      :dev ->
        cache_port = System.get_env("TUIST_CACHE_PORT") || "8087"
        execute seed_sql("http://localhost:#{cache_port}", "Local Dev")

      :test ->
        execute seed_sql("https://cache-eu-central-test.tuist.dev", "EU Central Test")
        execute seed_sql("https://cache-us-east-test.tuist.dev", "US East Test")

      _ ->
        :ok
    end
  end

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
