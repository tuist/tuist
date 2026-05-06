defmodule Tuist.Kura.Server do
  @moduledoc """
  A Kura server allocated for a single account, in a single region.

  Identity is `(account, region)`: an account can light up Kura in as
  many regions as it needs, but only one server per region.

  Lifecycle:

      provisioning → active      ↘
                     ↓              destroying → destroyed
                   failed

  `url` and `current_image_tag` are populated when the server first
  reaches `:active` and updated on subsequent successful deployments.

  `provisioner_node_ref` is the opaque handle the provisioner returned
  from `provision/3`. The control plane stores it untouched and hands
  it back to the provisioner for `rollout/3` and `destroy/1`. For the
  helm-Kubernetes provisioner it's the helm release name.

  Per-server install and update attempts live in `kura_deployments` via
  `kura_server_id`. These rows are the deployment records the
  provisioner later applies with its own rollout strategy.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Kura.Deployment

  @status_mappings [provisioning: 0, active: 1, failed: 2, destroying: 3, destroyed: 4]
  @statuses Keyword.keys(@status_mappings)
  @allowed_status_transitions %{
    provisioning: [:provisioning, :active, :failed, :destroying],
    active: [:active, :failed, :destroying],
    failed: [:failed, :active, :destroying],
    destroying: [:destroying, :destroyed],
    destroyed: [:destroyed]
  }
  @image_tag_format ~r/^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/
  @image_tag_message "must be a Kura image tag like 0.5.2, 0.5.2-rc.1, or v0.5.2"
  @provisioner_node_ref_format ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
  @provisioner_node_ref_message "must be a valid Kubernetes RFC1123 label"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_servers" do
    field :region, :string
    field :status, Ecto.Enum, values: @status_mappings, default: :provisioning
    field :url, :string
    field :current_image_tag, :string
    field :provisioner_node_ref, :string

    belongs_to :account, Account

    has_many :deployments, Deployment, foreign_key: :kura_server_id

    # Sub-second precision so deployments inserted in quick succession
    # keep a deterministic order when listed.
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def create_changeset(server \\ %__MODULE__{}, attrs) do
    server
    |> cast(attrs, [
      :account_id,
      :region,
      :provisioner_node_ref
    ])
    |> validate_required([:account_id, :region, :provisioner_node_ref])
    |> validate_format(:provisioner_node_ref, @provisioner_node_ref_format, message: @provisioner_node_ref_message)
    |> validate_length(:provisioner_node_ref, max: 53)
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
      :provisioner_node_ref
    ])
    |> validate_required([:status])
    |> validate_format(:current_image_tag, @image_tag_format, message: @image_tag_message)
    |> validate_length(:current_image_tag, max: 128)
    |> validate_active_fields()
    |> validate_status_transition()
  end

  defp validate_active_fields(changeset) do
    if get_field(changeset, :status) == :active do
      validate_required(changeset, [:url, :current_image_tag])
    else
      changeset
    end
  end

  defp validate_status_transition(%Ecto.Changeset{errors: errors} = changeset) do
    if Keyword.has_key?(errors, :status) do
      changeset
    else
      from = changeset.data.status || :provisioning
      to = get_field(changeset, :status)

      if to in Map.get(@allowed_status_transitions, from, []) do
        changeset
      else
        add_error(changeset, :status, "cannot transition from #{from} to #{to}")
      end
    end
  end
end
