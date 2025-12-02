defmodule Tuist.Runners.RunnerJob do
  @moduledoc """
  Represents a job tracking for Tuist Runners.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "runner_jobs" do
    field :github_job_id, :integer
    field :run_id, :integer
    field :org, :string
    field :repo, :string
    field :labels, {:array, :string}

    field :status, Ecto.Enum,
      values: [
        pending: 0,
        spawning: 1,
        running: 2,
        cleanup: 3,
        completed: 4,
        failed: 5,
        cancelled: 6
      ],
      default: :pending

    field :vm_name, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :github_workflow_url, :string
    field :github_runner_name, :string
    field :error_message, :string

    belongs_to :host, Tuist.Runners.RunnerHost, foreign_key: :host_id
    belongs_to :organization, Tuist.Runners.RunnerOrganization, foreign_key: :organization_id

    timestamps(type: :utc_datetime)
  end

  def changeset(runner_job, attrs) do
    runner_job
    |> cast(attrs, [
      :id,
      :github_job_id,
      :run_id,
      :org,
      :repo,
      :labels,
      :status,
      :host_id,
      :vm_name,
      :started_at,
      :completed_at,
      :organization_id,
      :github_workflow_url,
      :github_runner_name,
      :error_message
    ])
    |> validate_required([
      :id,
      :github_job_id,
      :run_id,
      :org,
      :repo,
      :labels,
      :status
    ])
    |> validate_number(:github_job_id, greater_than: 0)
    |> validate_number(:run_id, greater_than: 0)
    |> unique_constraint(:github_job_id)
    |> foreign_key_constraint(:host_id)
    |> foreign_key_constraint(:organization_id)
    |> validate_transition()
  end

  defp validate_transition(changeset) do
    old_status = changeset.data.status

    case {old_status, get_change(changeset, :status)} do
      {_, nil} -> changeset
      {nil, _} -> changeset
      {old, new} -> validate_status_transition(changeset, old, new)
    end
  end

  defp validate_status_transition(changeset, old_status, new_status) do
    valid_transitions = %{
      pending: [:spawning, :cancelled],
      spawning: [:running, :failed, :cancelled],
      running: [:cleanup, :failed, :cancelled],
      cleanup: [:completed, :failed],
      completed: [],
      failed: [],
      cancelled: []
    }

    if new_status in valid_transitions[old_status] do
      changeset
    else
      add_error(changeset, :status, "invalid transition from #{old_status} to #{new_status}")
    end
  end

  def pending_query do
    from job in __MODULE__, where: job.status == :pending
  end

  def running_query do
    from job in __MODULE__, where: job.status in [:spawning, :running, :cleanup]
  end

  def by_github_job_id_query(github_job_id) do
    from job in __MODULE__, where: job.github_job_id == ^github_job_id
  end

  def by_org_query(org) do
    from job in __MODULE__, where: job.org == ^org
  end

  def by_host_query(host_id) do
    from job in __MODULE__, where: job.host_id == ^host_id
  end
end
