defmodule Tuist.Runners.RunnerJob do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Runners.RunnerConfiguration

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7

  @statuses [:queued, :provisioning, :in_progress, :completed, :failed, :cancelled]

  @valid_transitions %{
    queued: [:provisioning, :failed, :cancelled],
    provisioning: [:in_progress, :completed, :failed, :cancelled],
    in_progress: [:completed, :failed, :cancelled],
    completed: [],
    failed: [],
    cancelled: []
  }

  schema "runner_jobs" do
    field :github_workflow_job_id, :integer
    field :github_run_id, :integer
    field :github_repository_full_name, :string
    field :status, Ecto.Enum, values: @statuses, default: :queued
    field :orchard_vm_name, :string
    field :runner_name, :string
    field :tart_image, :string
    field :labels, {:array, :string}, default: []
    field :conclusion, :string
    field :queued_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :error_message, :string

    belongs_to :runner_configuration, RunnerConfiguration
    belongs_to :account, Account, type: :integer

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :runner_configuration_id,
      :account_id,
      :github_workflow_job_id,
      :github_run_id,
      :github_repository_full_name,
      :tart_image,
      :labels,
      :queued_at
    ])
    |> validate_required([
      :runner_configuration_id,
      :account_id,
      :github_workflow_job_id,
      :github_repository_full_name
    ])
    |> unique_constraint(:github_workflow_job_id)
    |> foreign_key_constraint(:runner_configuration_id)
    |> foreign_key_constraint(:account_id)
  end

  def update_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :status,
      :orchard_vm_name,
      :runner_name,
      :tart_image,
      :conclusion,
      :started_at,
      :completed_at,
      :error_message
    ])
    |> validate_status_transition()
  end

  defp validate_status_transition(changeset) do
    case {changeset.data.status, get_change(changeset, :status)} do
      {_current, nil} ->
        changeset

      {current, next} ->
        allowed = Map.get(@valid_transitions, current, [])

        if next in allowed do
          changeset
        else
          add_error(changeset, :status, "cannot transition from #{current} to #{next}")
        end
    end
  end
end
