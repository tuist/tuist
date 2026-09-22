defmodule Tuist.OnceEvents.Action do
  @moduledoc """
  One declared action within a Once run. Sub-target granularity: several
  actions can share the same `target_execution_id` (different
  `capability` or `action_index`). Together with the parent run they
  reconstruct the actions view the dashboard renders.

  Timestamps are `:utc_datetime_usec` so 1000 actions completing in
  the same second don't collapse into one flame-graph slice.
  """
  use Ecto.Schema

  alias Tuist.OnceEvents.Run

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_actions" do
    belongs_to :run, Run, foreign_key: :once_run_id, type: UUIDv7
    field :run_id, :string
    field :project_id, :integer

    field :target_execution_id, :string
    field :capability, :string
    field :action_index, :integer, default: 0
    field :identifier, :string

    field :result, :string
    field :was_cached, :boolean, default: false
    field :exit_code, :integer, default: 0
    field :duration_ms, :integer, default: 0

    # Row-per-worker rendering on the Timeline tab keys off this.
    # Empty string when the client didn't report one.
    field :worker_id, :string, default: ""

    # Wall-time split between the two phases the CLI observes for
    # every action. The Timeline module renders each as its own
    # sub-span on the worker's lane so cache-hit builds show what
    # filled the wall clock instead of a run of 1 ms dashes. Their
    # sum is <= duration_ms; zero for cached-replay actions.
    field :prepare_ms, :integer, default: 0
    field :execute_ms, :integer, default: 0

    # Hex digest the action probed against the CAS (Bazel's
    # `action_digest`). Shown as the Cache key column on the
    # Cacheable Actions view.
    field :cache_key, :string, default: ""

    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
