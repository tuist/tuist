defmodule Atlas.Orbit.Thread do
  @moduledoc false
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Participant
  alias Atlas.Users.User

  @kinds ~w(private shared)
  @statuses ~w(active archived)
  @origins ~w(manual signal)

  schema "orbit_threads" do
    field :kind, :string
    field :title, :string
    field :status, :string, default: "active"
    field :summary, :string, default: ""
    field :origin, :string, default: "manual"
    field :source_type, :string
    field :source_id, :string
    field :request_id, Ecto.UUID
    field :required_scopes, {:array, :string}, default: []
    field :last_seq, :integer, default: 0

    belongs_to :owner, User
    has_many :participants, Participant
    has_many :messages, Message

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :kind,
      :title,
      :summary,
      :origin,
      :source_type,
      :source_id,
      :owner_id,
      :required_scopes,
      :request_id
    ])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:kind, :title])
    |> validate_length(:title, max: 200)
    |> validate_length(:summary, max: 2_000)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:origin, @origins)
    |> unique_constraint([:owner_id, :request_id], name: :orbit_threads_private_request_index)
    |> unique_constraint([:source_type, :source_id], name: :orbit_threads_active_signal_source_index)
  end
end
