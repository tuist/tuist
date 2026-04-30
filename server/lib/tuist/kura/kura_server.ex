defmodule Tuist.Kura.KuraServer do
  @moduledoc """
  A Kura server provisioned for a single account, in a single region.

  Identity is `(account, region)`: an account can light up Kura in as
  many regions as it needs, but only one server per region. `spec` is
  a capacity knob (CPU/memory/volume per node), not part of identity.

  Lifecycle:

      provisioning → active      ↘
                     ↓              destroying → destroyed
                   failed

  `url` and `current_image_tag` are populated when the server first
  reaches `:active` and updated on subsequent successful deployments.

  `provider_node_ref` is the opaque handle the provider returned from
  `provision/3`. The control plane stores it untouched and hands it
  back to the provider for `rollout/3` and `destroy/1`. For the
  helm/Kubernetes provider it's the helm release name.
  `provider_metadata` is a JSON bag the provider uses to remember
  anything else it needs between calls (instance type, zone, peer
  seeding info, etc.).

  Per-server lifecycle events (rollout attempts) live in
  `kura_deployments` via `kura_server_id`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Kura.KuraDeployment

  @specs [:small, :medium, :large]
  @statuses [:provisioning, :active, :failed, :destroying, :destroyed]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_servers" do
    field :region, :string
    field :spec, Ecto.Enum, values: Enum.with_index(@specs), default: :medium
    field :volume_size_gi, :integer
    field :status, Ecto.Enum, values: Enum.with_index(@statuses), default: :provisioning
    field :url, :string
    field :current_image_tag, :string
    field :provider_node_ref, :string
    field :provider_metadata, :map, default: %{}

    belongs_to :account, Account

    has_many :deployments, KuraDeployment, foreign_key: :kura_server_id

    timestamps(type: :utc_datetime_usec)
  end

  def specs, do: @specs
  def statuses, do: @statuses

  def create_changeset(server \\ %__MODULE__{}, attrs) do
    server
    |> cast(attrs, [
      :account_id,
      :region,
      :spec,
      :volume_size_gi,
      :provider_node_ref,
      :provider_metadata
    ])
    |> validate_required([:account_id, :region, :spec, :volume_size_gi])
    |> validate_number(:volume_size_gi, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_change(:region, fn :region, value ->
      if Tuist.Kura.Regions.exists?(value),
        do: [],
        else: [region: "is not a registered region"]
    end)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :region],
      name: :kura_servers_account_region_active_index,
      message: "an active Kura server already exists for this account and region"
    )
  end

  def status_changeset(server, attrs) do
    server
    |> cast(attrs, [
      :status,
      :url,
      :current_image_tag,
      :provider_node_ref,
      :provider_metadata
    ])
    |> validate_required([:status])
  end
end
