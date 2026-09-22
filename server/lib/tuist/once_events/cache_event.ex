defmodule Tuist.OnceEvents.CacheEvent do
  @moduledoc """
  Projected state for one `CacheUpload`, `CacheDownload`, or
  `CacheStoreReused` wire event from `once.events.v1`.

  Feeds the Once run dashboard's Cache tab: the Cacheable Actions
  view lists rows keyed by target execution and cache decision, and
  the Content Objects view lists distinct content-address digests
  with their sizes.
  """
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_cache_events" do
    field :once_run_id, UUIDv7
    field :run_id, :string
    field :project_id, :integer

    field :kind, :string
    field :target_execution_id, :string
    field :cache_decision_id, :string
    field :tier, :string
    field :category, :string

    field :content_hash, :string
    field :content_size_bytes, :integer, default: 0
    field :bytes_transferred, :integer, default: 0
    field :duration_ms, :integer, default: 0
    field :outcome, :string

    field :observed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
