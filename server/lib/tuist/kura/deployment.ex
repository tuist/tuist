defmodule Tuist.Kura.Deployment do
  @moduledoc """
  One deployment record for a `Server`.

  Created by `Tuist.Kura.create_server/1` (initial install) or
  `create_deployment/2` (version bump), picked up by
  `Tuist.Kura.Workers.RolloutWorker` via Oban. The worker dispatches
  to the region's provisioner, which decides what "rollout" means.

  In product terms these rows track install and update attempts for a
  Kura server. The provisioner's rollout logic is how a deployment gets
  applied, especially for staged updates.

  Per-line stdout/stderr streams to the `kura_deployment_log_lines`
  ClickHouse table keyed by `id` so /ops can tail in real time.

  `cluster_id` is an audit field: which backing cluster the deployment
  actually targeted, captured at insert time so operators reading the
  deployment list see something concrete (`"eu-1"`) rather than the
  abstract region (`"eu"`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Kura.Server

  @statuses [:pending, :running, :succeeded, :failed, :cancelled]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_deployments" do
    field :cluster_id, :string
    field :image_tag, :string
    field :status, Ecto.Enum, values: Enum.with_index(@statuses), default: :pending
    field :error_message, :string
    field :oban_job_id, :integer
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :kura_server, Server, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(deployment \\ %__MODULE__{}, attrs) do
    deployment
    |> cast(attrs, [:cluster_id, :image_tag, :kura_server_id])
    |> validate_required([:cluster_id, :image_tag, :kura_server_id])
    |> validate_format(:image_tag, ~r/^\d+\.\d+\.\d+$/, message: "must be a Kura semver like 0.5.2")
    |> foreign_key_constraint(:kura_server_id)
  end

  def status_changeset(deployment, attrs) do
    deployment
    |> cast(attrs, [:status, :error_message, :oban_job_id, :started_at, :finished_at])
    |> validate_required([:status])
  end
end
