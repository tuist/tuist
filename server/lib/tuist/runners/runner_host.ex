defmodule Tuist.Runners.RunnerHost do
  @moduledoc """
  Represents a Mac host registration for Tuist Runners.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Tuist.Runners.RunnerJob

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "runner_hosts" do
    field :name, :string
    field :ip, :string
    field :ssh_port, :integer
    field :capacity, :integer
    field :status, Ecto.Enum, values: [online: 0, offline: 1, maintenance: 2, error: 3]
    field :chip_type, Ecto.Enum, values: [m1: 0, m2: 1, m3: 2, m4: 3, intel: 4]
    field :ram_gb, :integer
    field :storage_gb, :integer
    field :last_heartbeat_at, :utc_datetime
    field :github_runner_token, :binary

    has_many :jobs, RunnerJob, foreign_key: :host_id

    timestamps(type: :utc_datetime)
  end

  def changeset(runner_host, attrs) do
    runner_host
    |> cast(attrs, [
      :id,
      :name,
      :ip,
      :ssh_port,
      :capacity,
      :status,
      :chip_type,
      :ram_gb,
      :storage_gb,
      :last_heartbeat_at,
      :github_runner_token
    ])
    |> validate_required([
      :id,
      :name,
      :ip,
      :ssh_port,
      :capacity,
      :status,
      :chip_type,
      :ram_gb,
      :storage_gb
    ])
    |> validate_number(:ssh_port, greater_than: 0, less_than: 65_536)
    |> validate_number(:capacity, greater_than: 0)
    |> validate_number(:ram_gb, greater_than: 0)
    |> validate_number(:storage_gb, greater_than: 0)
    |> validate_format(:ip, ~r/^(\d{1,3}\.){3}\d{1,3}$/)
    |> unique_constraint(:name)
    |> unique_constraint(:ip)
  end

  @active_job_statuses [:pending, :spawning, :running, :cleanup]

  def online_query do
    from host in __MODULE__, where: host.status == :online
  end

  def available_query do
    active_jobs_subquery =
      from(job in RunnerJob,
        where: job.status in @active_job_statuses,
        group_by: job.host_id,
        select: %{host_id: job.host_id, count: count(job.id)}
      )

    from host in online_query(),
      left_join: jobs in subquery(active_jobs_subquery),
      on: jobs.host_id == host.id,
      where: coalesce(jobs.count, 0) < host.capacity,
      select: host
  end

  def with_active_job_count_query do
    active_jobs_subquery =
      from(job in RunnerJob,
        where: job.status in @active_job_statuses,
        group_by: job.host_id,
        select: %{host_id: job.host_id, count: count(job.id)}
      )

    from host in online_query(),
      left_join: jobs in subquery(active_jobs_subquery),
      on: jobs.host_id == host.id,
      select: %{host: host, active_jobs: coalesce(jobs.count, 0)}
  end

  def by_available_capacity_query do
    active_jobs_subquery =
      from(job in RunnerJob,
        where: job.status in @active_job_statuses,
        group_by: job.host_id,
        select: %{host_id: job.host_id, count: count(job.id)}
      )

    from host in online_query(),
      left_join: jobs in subquery(active_jobs_subquery),
      on: jobs.host_id == host.id,
      where: coalesce(jobs.count, 0) < host.capacity,
      order_by: [asc: coalesce(jobs.count, 0)],
      select: host
  end
end
