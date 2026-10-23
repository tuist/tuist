defmodule Atlas.Orbit.Run do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Encrypted.Binary
  alias Atlas.Inference.ModelBinding
  alias Atlas.Orbit.Thread
  alias Atlas.Users.User

  @active_statuses ~w(queued running)

  schema "orbit_runs" do
    field :status, :string, default: "queued"
    field :trigger_seq, :integer
    field :resume_count, :integer, default: 0
    field :session_id, :string
    field :checkpoint, Binary, redact: true
    field :checkpoint_turn, :integer
    field :error_category, :string
    field :cancel_requested_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :heartbeat_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec

    belongs_to :thread, Thread
    belongs_to :initiator, User
    belongs_to :acting_user, User
    belongs_to :model_binding, ModelBinding, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def active_statuses, do: @active_statuses
end
