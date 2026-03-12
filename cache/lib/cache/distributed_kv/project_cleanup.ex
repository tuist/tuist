defmodule Cache.DistributedKV.ProjectCleanup do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "distributed_kv_project_cleanups" do
    field :account_handle, :string, primary_key: true
    field :project_handle, :string, primary_key: true
    field :cleanup_started_at, :utc_datetime_usec
    field :lease_expires_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(cleanup, attrs) do
    cleanup
    |> cast(attrs, [:account_handle, :project_handle, :cleanup_started_at, :lease_expires_at, :updated_at])
    |> validate_required([:account_handle, :project_handle, :cleanup_started_at, :lease_expires_at, :updated_at])
  end
end
