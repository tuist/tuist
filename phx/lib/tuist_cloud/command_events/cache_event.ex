defmodule TuistCloud.CommandEvents.CacheEvent do
  @moduledoc ~S"""
  A module that represents the cache events.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "cache_events" do
    field :name, :string
    field :event_type, Ecto.Enum, values: [download: 0, upload: 1]
    field :size, :integer
    timestamps(inserted_at: :created_at)

    belongs_to :project, TuistCloud.Accounts.Project
  end

  def create_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :project_id,
      :name,
      :event_type,
      :size,
      :created_at
    ])
    |> validate_required([:project_id, :name, :event_type, :size])
  end
end
