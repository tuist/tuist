defmodule Symptoms.Repo.Migrations.CreateDetectionState do
  use Ecto.Migration

  def change do
    # The catalogue. An entity is unique per (environment, service, kind, key);
    # `aliases` are other keys of the same kind that resolve to it.
    create table(:entities) do
      add :environment, :text, null: false
      add :service, :text, null: false
      add :kind, :text, null: false
      add :key, :text, null: false
      add :family, :text, null: false
      add :aliases, {:array, :text}, null: false, default: []
      add :first_seen_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :last_evidence_at, :utc_datetime_usec
      add :retired_at, :utc_datetime_usec
      add :unknown, :boolean, null: false, default: false
      add :unknown_since, :utc_datetime_usec
      timestamps()
    end

    create unique_index(:entities, [:environment, :service, :kind, :key])
    create index(:entities, [:aliases], using: :gin)
    create index(:entities, [:family])

    # The start of an entity's current degraded run, per pipeline.
    create table(:degraded_runs, primary_key: false) do
      add :entity_id, references(:entities, on_delete: :delete_all), primary_key: true
      add :window_seconds, :integer, primary_key: true
      add :since, :utc_datetime_usec, null: false
    end

    # Caller → callee edges, replaced per source by `Symptoms.Store.put_edges/2`.
    create table(:edges) do
      add :source, :text, null: false
      add :caller_id, references(:entities, on_delete: :delete_all), null: false
      add :callee_id, references(:entities, on_delete: :delete_all), null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:edges, [:source, :caller_id, :callee_id])

    # Raw statistics per (entity, source, window), kept 35 days.
    create table(:stream_windows) do
      add :entity_id, references(:entities, on_delete: :delete_all), null: false
      add :source, :text, null: false
      add :phenomenon, :text, null: false
      add :window_seconds, :integer, null: false
      add :window_start, :utc_datetime_usec, null: false
      add :statistic, :float, null: false
      add :p, :float
      add :e, :float, null: false
      add :observed, :float
      add :expected, :float
      add :n, :bigint
      add :impact_unit, :text
      add :impact_rate, :float
      add :examples, {:array, :text}, null: false, default: []
      add :open_symptom, :boolean, null: false, default: false
      # The symptom a window's degraded run belongs to: the null history
      # leaves out only runs labelled bad or still open at board tier or above.
      add :symptom_id, :uuid
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:stream_windows, [:entity_id, :source, :window_seconds, :window_start])
    create index(:stream_windows, [:symptom_id], where: "symptom_id IS NOT NULL")
    create index(:stream_windows, [:source, :window_seconds, :window_start])
    create index(:stream_windows, [:window_start])

    # CUSUM per root key.
    create table(:detector_states, primary_key: false) do
      add :root_key, :text, primary_key: true
      add :cusum, :float, null: false, default: 0.0
      add :window_seconds, :integer, null: false
      add :last_window_start, :utc_datetime_usec, null: false
      add :quiet_windows, :integer, null: false, default: 0
      add :symptom_id, :uuid
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:source_weights) do
      add :phenomenon, :text, null: false
      add :source, :text, null: false
      add :weight, :float, null: false
      add :samples, :float, null: false, default: 0.0
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:source_weights, [:phenomenon, :source])

    # Platt parameters, page prices and thresholds keep their history: the
    # latest row is in force (Platt and thresholds per pipeline).
    create table(:platt_params) do
      add :a, :float, null: false
      add :b, :float, null: false
      add :window_seconds, :integer, null: false, default: 60
      add :kind, :text, null: false
      add :samples, :integer, null: false, default: 0
      add :details, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:price_settings) do
      add :day_price, :float, null: false
      add :night_price, :float, null: false
      add :floor_rate, :float, null: false
      add :reason, :text, null: false
      add :details, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:thresholds) do
      add :h, :float, null: false
      add :crossings, :integer, null: false
      add :entity_days, :float, null: false
      add :rate, :float, null: false
      add :window_seconds, :integer, null: false, default: 60
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create table(:symptoms, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :symptom_key, :text, null: false
      add :kind, :text, null: false, default: "detected"
      add :root_key, :text, null: false
      add :entity_id, references(:entities, on_delete: :nilify_all)
      add :phenomenon, :text, null: false
      add :state, :text, null: false
      add :tier, :text, null: false
      add :max_tier, :text, null: false
      add :revision, :integer, null: false, default: 0
      add :score, :float, null: false, default: 0.0
      add :max_score, :float, null: false, default: 0.0
      add :p_degraded, :float
      add :expected_cost, :float
      add :impact_unit, :text
      add :impact_rate, :float
      add :merged_into, :uuid
      add :charged, :boolean, null: false, default: false
      # Set only when a page was delivered; `page_logged_at` when paging was
      # off and the page was only logged.
      add :paged_at, :utc_datetime_usec
      add :page_logged_at, :utc_datetime_usec
      add :delayed_until, :utc_datetime_usec
      add :delay_probability, :float
      add :document, :map
      add :opened_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      add :last_revision_at, :utc_datetime_usec
      timestamps()
    end

    create index(:symptoms, [:symptom_key, :resolved_at])
    create index(:symptoms, [:root_key], where: "state = 'open'")
    create index(:symptoms, [:state, :tier])

    execute "CREATE SEQUENCE symptom_revision_seq", "DROP SEQUENCE symptom_revision_seq"

    # The append-only revision log, kept 30 days. `seq` is drawn from
    # `symptom_revision_seq` under an advisory lock, so revisions commit in
    # `seq` order.
    create table(:symptom_revisions, primary_key: false) do
      add :seq, :bigint, primary_key: true
      add :symptom_id, references(:symptoms, type: :uuid, on_delete: :delete_all), null: false
      add :revision, :integer, null: false
      add :document, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:symptom_revisions, [:symptom_id, :revision])
    create index(:symptom_revisions, [:inserted_at])

    create table(:audit_events) do
      add :kind, :text, null: false
      add :entity_id, :bigint
      add :symptom_id, :uuid
      add :data, :map, null: false, default: %{}
      add :at, :utc_datetime_usec, null: false
    end

    create index(:audit_events, [:kind, :at])
    create index(:audit_events, [:symptom_id])

    # Change events from sources' `changes/2`.
    create table(:changes) do
      add :source, :text, null: false
      add :kind, :text, null: false
      add :category, :text, null: false
      add :ref, :text, null: false
      add :at, :utc_datetime_usec, null: false
      add :service, :text
      add :touched_entity_ids, {:array, :bigint}, null: false, default: []
      add :before, :map
      add :after, :map
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:changes, [:source, :kind, :ref])
    create index(:changes, [:at])

    # Per-version request and error counts from `Symptoms.Store.put_version_counts/2`.
    create table(:version_counts) do
      add :entity_id, references(:entities, on_delete: :delete_all), null: false
      add :version, :text, null: false
      add :window_seconds, :integer, null: false
      add :window_start, :utc_datetime_usec, null: false
      add :errors, :bigint, null: false
      add :total, :bigint, null: false
      add :p95_ms, :float
      # Log-bucket latency histogram (`%{bucket => count}`) on 5-minute windows.
      add :histogram, :map
    end

    create unique_index(:version_counts, [:entity_id, :version, :window_seconds, :window_start])
    create index(:version_counts, [:window_start])

    # Version-against-version e-process state per (change, entity).
    create table(:version_tests) do
      add :change_id, references(:changes, on_delete: :delete_all), null: false
      add :entity_id, references(:entities, on_delete: :delete_all), null: false
      # `error_share` or `latency_exceedance`.
      add :test, :text, null: false, default: "error_share"
      add :log_weights, {:array, :float}, null: false
      add :e, :float, null: false, default: 1.0
      add :status, :text, null: false, default: "running"
      add :last_window_start, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:version_tests, [:change_id, :entity_id, :test])

    create table(:baseline_reanchors) do
      add :entity_id, references(:entities, on_delete: :delete_all), null: false
      add :change_id, references(:changes, on_delete: :delete_all), null: false
      add :from_version, :text
      add :to_version, :text
      add :status, :text, null: false
      add :error_ratio, :float
      add :p95_ratio, :float
      add :symptom_id, :uuid
      add :at, :utc_datetime_usec, null: false
    end

    create unique_index(:baseline_reanchors, [:change_id, :entity_id])
    create index(:baseline_reanchors, [:entity_id, :at])

    # The combined score per root per window, for replays (kept 35 days).
    # Only windows with a positive CUSUM or an attached symptom are kept.
    create table(:root_scores) do
      add :root_key, :text, null: false
      add :window_seconds, :integer, null: false
      add :window_start, :utc_datetime_usec, null: false
      add :x, :float, null: false
      add :score, :float, null: false
      add :impact, :float, null: false, default: 0.0
      add :symptom_id, :uuid
    end

    create unique_index(:root_scores, [:root_key, :window_seconds, :window_start])
    create index(:root_scores, [:window_start])
    create index(:root_scores, [:symptom_id])

    create table(:pipeline_runs, primary_key: false) do
      add :window_seconds, :integer, primary_key: true
      add :window_start, :utc_datetime_usec, primary_key: true
      add :records, :integer, null: false
      add :entities, :integer, null: false
      add :finished_at, :utc_datetime_usec, null: false
    end

    create table(:source_statuses, primary_key: false) do
      add :source, :text, primary_key: true
      add :last_success_at, :utc_datetime_usec
      add :last_window_end, :utc_datetime_usec
      add :last_error, :text
      add :last_error_at, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec, null: false
    end

    # Which source last produced evidence for an entity: the entities each
    # source is expected to report (`:entities`).
    create table(:source_entities, primary_key: false) do
      add :source, :text, primary_key: true
      add :entity_id, references(:entities, on_delete: :delete_all), primary_key: true
      add :last_seen_at, :utc_datetime_usec, null: false
    end

    # The latest `baselines/2` result of a source, `:erlang.term_to_binary`
    # of `%{entity_tuple => baseline}`.
    create table(:source_baselines, primary_key: false) do
      add :source, :text, primary_key: true
      add :data, :binary, null: false
      add :entities, :integer, null: false
      add :computed_at, :utc_datetime_usec, null: false
    end

    create table(:labels, primary_key: false) do
      add :symptom_id, references(:symptoms, type: :uuid, on_delete: :delete_all), primary_key: true
      add :outcome, :text, null: false
      add :independent, :boolean, null: false
      add :cause, :text
      add :weight, :float, null: false
      add :score, :float, null: false
      add :max_tier, :text, null: false
      add :missed, :boolean, null: false
      add :delay_probability, :float
      add :delayed, :boolean, null: false, default: false
      add :phenomena, {:array, :map}, null: false, default: []
      add :confirmed_at, :utc_datetime_usec, null: false
      timestamps()
    end

    # The read-back cursor and the mirrored human state from the Tuist server.
    create table(:state_cursors, primary_key: false) do
      add :name, :text, primary_key: true
      add :cursor, :bigint, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:human_acks, primary_key: false) do
      add :symptom_id, :uuid, primary_key: true
      add :revision, :integer
      add :acked_at, :utc_datetime_usec, null: false
      add :change_seq, :bigint, null: false
    end

    create table(:human_mutes) do
      add :environment, :text, null: false
      add :service, :text, null: false
      add :kind, :text, null: false
      add :key, :text, null: false
      add :phenomenon, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :symptom_id, :uuid
      add :change_seq, :bigint, null: false
    end

    create unique_index(:human_mutes, [:environment, :service, :kind, :key, :phenomenon])

    create table(:human_outcomes, primary_key: false) do
      add :symptom_id, :uuid, primary_key: true
      add :outcome, :text, null: false
      add :confirmed_at, :utc_datetime_usec, null: false
      add :change_seq, :bigint, null: false
    end

    # Investigations, kept as the server sends them.
    create table(:human_events) do
      add :kind, :text, null: false
      add :symptom_id, :uuid
      add :data, :map, null: false
      add :change_seq, :bigint, null: false
    end

    create unique_index(:human_events, [:kind, :change_seq])
    create index(:human_events, [:symptom_id])
  end
end
