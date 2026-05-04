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

  @status_mappings [pending: 0, running: 1, succeeded: 2, failed: 3, cancelled: 4]
  @statuses Keyword.keys(@status_mappings)
  @allowed_status_transitions %{
    pending: [:pending, :running, :failed, :cancelled],
    running: [:running, :succeeded, :failed, :cancelled],
    succeeded: [:succeeded],
    failed: [:failed],
    cancelled: [:cancelled]
  }
  @image_tag_format ~r/^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/
  @image_tag_message "must be a Kura image tag like 0.5.2, 0.5.2-rc.1, or v0.5.2"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_deployments" do
    field :cluster_id, :string
    field :image_tag, :string
    field :status, Ecto.Enum, values: @status_mappings, default: :pending
    field :error_message, :string
    field :oban_job_id, :integer
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :kura_server, Server, type: :binary_id

    # Sub-second precision so deployments inserted in quick succession
    # keep a deterministic order when listed.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(deployment \\ %__MODULE__{}, attrs) do
    deployment
    |> cast(attrs, [:cluster_id, :image_tag, :kura_server_id])
    |> validate_required([:cluster_id, :image_tag, :kura_server_id])
    |> validate_format(:image_tag, @image_tag_format, message: @image_tag_message)
    |> validate_length(:image_tag, max: 128)
    |> foreign_key_constraint(:kura_server_id)
  end

  def status_changeset(deployment, attrs) do
    deployment
    |> cast(attrs, [:status, :error_message, :oban_job_id, :started_at, :finished_at])
    |> validate_required([:status])
    |> validate_status_transition()
  end

  defp validate_status_transition(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :status) do
      changeset
    else
      from = changeset.data.status || :pending
      to = get_field(changeset, :status)

      if to in Map.get(@allowed_status_transitions, from, []) do
        changeset
      else
        add_error(changeset, :status, "cannot transition from #{from} to #{to}")
      end
    end
  end
end
