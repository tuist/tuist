defmodule Tuist.Runners.CacheVolumes.Usage do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "runner_cache_volume_uses" do
    belongs_to(:volume, Tuist.Runners.CacheVolumes.Volume, type: :binary_id)
    field(:generation, :integer)
    field(:parent_id, :binary_id)
    field(:workflow_job_id, :integer)
    field(:workflow_run_id, :integer)
    field(:job_name, :string, virtual: true)
    field(:workflow_name, :string, virtual: true)
    field(:pod_name, :string)
    field(:pod_uid, :string)
    field(:node_name, :string)
    field(:can_publish, :boolean)
    field(:status, :string, default: "allocated")
    field(:warm, :boolean)
    field(:size_bytes, :integer)
    field(:capacity_bytes, :integer)
    field(:attach_ms, :integer)
    field(:last_reported_at, :utc_datetime_usec)
    field(:attached_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime)
  end
end
