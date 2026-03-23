defmodule Cache.DistributedKV.Project do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "projects" do
    field :account_handle, :string, primary_key: true
    field :project_handle, :string, primary_key: true
    field :last_cleanup_at, :utc_datetime_usec
    field :cleanup_lease_expires_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:account_handle, :project_handle, :last_cleanup_at, :cleanup_lease_expires_at, :updated_at])
    |> validate_required([:account_handle, :project_handle, :last_cleanup_at, :cleanup_lease_expires_at, :updated_at])
  end
end
