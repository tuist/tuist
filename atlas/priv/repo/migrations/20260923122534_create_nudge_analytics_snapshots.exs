defmodule Atlas.Repo.Migrations.CreateNudgeAnalyticsSnapshots do
  use Ecto.Migration

  def change do
    create table(:nudge_account_metric_buckets, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      # Non-overlapping completed UTC-day bucket. Signals sum the last N rows
      # to compute rolling numerator/denominator on read; a bucket per day
      # keeps that composition safe from double counting.
      add :bucket_date, :date, null: false

      add :daily_cache_hits, :bigint, null: false, default: 0
      add :daily_cache_lookups, :bigint, null: false, default: 0
      add :daily_selective_targets, :bigint, null: false, default: 0
      add :daily_selective_hits, :bigint, null: false, default: 0

      add :refresh_status, :string, null: false, default: "ok"
      add :refresh_error, :text
      add :computed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:nudge_account_metric_buckets, [:account_id, :bucket_date])
    create index(:nudge_account_metric_buckets, [:account_id, :refresh_status])

    create constraint(:nudge_account_metric_buckets, :nudge_account_metric_buckets_status_check,
             check: "refresh_status IN ('ok', 'failed')"
           )

    create table(:nudge_account_air_status, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :period_start, :date, null: false
      add :metric, :string, null: false
      add :distinct_thresholds_delivered, :integer, null: false, default: 0
      add :first_crossed_at, :utc_datetime

      add :refresh_status, :string, null: false, default: "ok"
      add :refresh_error, :text
      add :computed_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:nudge_account_air_status, [:account_id, :period_start, :metric])
    create index(:nudge_account_air_status, [:account_id, :refresh_status])

    create constraint(:nudge_account_air_status, :nudge_account_air_status_status_check,
             check: "refresh_status IN ('ok', 'failed')"
           )
  end
end
