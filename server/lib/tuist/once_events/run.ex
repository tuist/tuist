defmodule Tuist.OnceEvents.Run do
  @moduledoc """
  Projected state for one `once` command reported over `once.events.v1`.

  One row per client-minted `run_id` within a project. Rolls up totals as
  `Tuist.OnceEvents.Action` rows are ingested so the LiveView can render
  a live count without a per-request aggregation query.
  """
  use Ecto.Schema

  alias Tuist.OnceEvents.Action

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_runs" do
    field :run_id, :string
    field :project_id, :integer

    field :kind, :string, default: "build"

    field :once_version, :string
    field :protocol_version, :string
    field :host_class, :string
    field :git_rev, :string
    field :git_dirty, :boolean, default: false
    field :argv_normalized, :map, default: %{}
    field :argv_hash_key_id, :string
    field :safe_literal_allowlist_version, :string
    field :cwd_relative, :string
    field :env_fingerprint, :string
    field :root_graph_digest, :map, default: %{}
    field :effective_limits, :map, default: %{}
    field :command_display, :string

    field :finalization, :string, default: "active"
    field :exit_status, :integer
    field :cancellation_reason, :string
    field :wall_ms, :integer

    field :total_actions, :integer, default: 0
    field :cached_actions, :integer, default: 0
    field :executed_actions, :integer, default: 0
    field :failed_actions, :integer, default: 0

    field :cache_bytes_downloaded, :integer, default: 0
    field :cache_bytes_uploaded, :integer, default: 0
    field :cache_bytes_saved, :integer, default: 0
    field :cache_action_read_count, :integer, default: 0
    field :cache_action_read_ms_total, :integer, default: 0
    field :cache_action_write_count, :integer, default: 0
    field :cache_action_write_ms_total, :integer, default: 0

    # Test roll-ups incremented as `TestCaseCompleted` events land
    # (see `OnceEvents.ingest_test_case_run/2`). Present on every
    # run row so the Tests page can render totals without joining
    # `once_test_case_runs`.
    field :test_case_count, :integer, default: 0
    field :passed_test_cases, :integer, default: 0
    field :failed_test_cases, :integer, default: 0
    field :skipped_test_cases, :integer, default: 0
    field :test_suite_count, :integer, default: 0

    field :started_at, :utc_datetime_usec
    field :finalized_at, :utc_datetime_usec
    field :heartbeat_at, :utc_datetime_usec

    has_many :actions, Action, foreign_key: :once_run_id
    has_many :cache_events, Tuist.OnceEvents.CacheEvent, foreign_key: :once_run_id
    has_many :test_case_runs, Tuist.OnceEvents.TestCaseRun, foreign_key: :once_run_id
    has_many :test_suite_runs, Tuist.OnceEvents.TestSuiteRun, foreign_key: :once_run_id

    # Event ingest orders rows by these, and a run emits many events per
    # millisecond, so the microsecond precision is load bearing.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end
end
