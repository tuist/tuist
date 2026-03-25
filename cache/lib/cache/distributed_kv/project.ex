defmodule Cache.DistributedKV.Project do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "projects" do
    field :account_handle, :string, primary_key: true
    field :project_handle, :string, primary_key: true
    field :active_cleanup_cutoff_at, :utc_datetime_usec
    field :cleanup_lease_expires_at, :utc_datetime_usec
    field :published_cleanup_generation, :integer
    field :published_cleanup_cutoff_at, :utc_datetime_usec
    field :cleanup_published_at, :utc_datetime_usec
    field :cleanup_event_id, :integer
    field :updated_at, :utc_datetime_usec
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :account_handle,
      :project_handle,
      :active_cleanup_cutoff_at,
      :cleanup_lease_expires_at,
      :published_cleanup_generation,
      :published_cleanup_cutoff_at,
      :cleanup_published_at,
      :cleanup_event_id,
      :updated_at
    ])
    |> validate_required([:account_handle, :project_handle, :updated_at])
  end
end
