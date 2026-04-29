defmodule Tuist.Kura.KuraServer do
  @moduledoc """
  A Kura mesh provisioned for a single account, on a single backing
  cluster, at a single spec (resource size). The `(account, cluster,
  spec)` triple is unique — an account can run multiple servers if it
  wants different specs in different regions, but not two of the same
  shape in the same cluster.

  Lifecycle:

      provisioning → active     ↘
                    ↓             destroying → destroyed
                  failed

  `url` and `current_image_tag` are populated when the server first
  reaches `:active` and updated on subsequent successful deployments.

  Per-server lifecycle events (the actual rollout attempts) live in
  `kura_deployments` via `kura_server_id`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Kura.KuraDeployment

  @specs [:small, :medium, :large]
  @statuses [:provisioning, :active, :failed, :destroying, :destroyed]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_servers" do
    field :cluster_id, :string
    field :spec, Ecto.Enum, values: Enum.with_index(@specs), default: :medium
    field :volume_size_gi, :integer
    field :status, Ecto.Enum, values: Enum.with_index(@statuses), default: :provisioning
    field :url, :string
    field :current_image_tag, :string

    belongs_to :account, Account
    belongs_to :requested_by, User, foreign_key: :requested_by_user_id

    has_many :deployments, KuraDeployment, foreign_key: :kura_server_id

    timestamps(type: :utc_datetime_usec)
  end

  def specs, do: @specs
  def statuses, do: @statuses

  def create_changeset(server \\ %__MODULE__{}, attrs) do
    server
    |> cast(attrs, [
      :account_id,
      :cluster_id,
      :spec,
      :volume_size_gi,
      :requested_by_user_id
    ])
    |> validate_required([:account_id, :cluster_id, :spec, :volume_size_gi])
    |> validate_number(:volume_size_gi, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_change(:cluster_id, fn :cluster_id, value ->
      if Tuist.Kura.Clusters.exists?(value),
        do: [],
        else: [cluster_id: "is not a registered cluster"]
    end)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:requested_by_user_id)
    |> unique_constraint([:account_id, :cluster_id, :spec],
      message: "an active Kura server already exists for this account, cluster, and spec"
    )
  end

  def status_changeset(server, attrs) do
    server
    |> cast(attrs, [:status, :url, :current_image_tag])
    |> validate_required([:status])
  end
end
