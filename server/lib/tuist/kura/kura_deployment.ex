defmodule Tuist.Kura.KuraDeployment do
  @moduledoc """
  One rollout attempt for a `KuraServer`.

  Created by `Tuist.Kura.create_server/1` (initial install) or
  `create_deployment/1` (version bump), picked up by
  `Tuist.Kura.Workers.RolloutWorker` via Oban. The worker dispatches
  to the region's provider, which decides what "rollout" means.

  Per-line stdout/stderr streams to the `kura_deployment_log_lines`
  ClickHouse table keyed by `id` so /ops can tail in real time.

  `cluster_id` is an audit field: which backing cluster the rollout
  actually targeted, populated from `region.provider_config.cluster_id`
  at insert. Operators reading the deployment list see something
  concrete (`"eu-1"`) rather than the abstract region (`"eu"`).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Kura.KuraServer

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

    belongs_to :account, Account
    belongs_to :requested_by, User, foreign_key: :requested_by_user_id
    belongs_to :kura_server, KuraServer, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(deployment \\ %__MODULE__{}, attrs) do
    deployment
    |> cast(attrs, [:account_id, :cluster_id, :image_tag, :requested_by_user_id, :kura_server_id])
    |> validate_required([:account_id, :cluster_id, :image_tag])
    |> validate_format(:image_tag, ~r/^\d+\.\d+\.\d+$/, message: "must be a Kura semver like 0.5.2")
    |> validate_change(:cluster_id, fn :cluster_id, value ->
      if known_cluster_id?(value),
        do: [],
        else: [cluster_id: "is not referenced by any region"]
    end)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:requested_by_user_id)
    |> foreign_key_constraint(:kura_server_id)
  end

  defp known_cluster_id?(value) when is_binary(value) do
    Enum.any?(Tuist.Kura.Regions.all(), &(&1.provider_config[:cluster_id] == value))
  end

  defp known_cluster_id?(_), do: false

  def status_changeset(deployment, attrs) do
    deployment
    |> cast(attrs, [:status, :error_message, :oban_job_id, :started_at, :finished_at])
    |> validate_required([:status])
  end
end
