defmodule Tuist.Kura.Server do
  @moduledoc """
  A Kura server allocated for a single account, in a single region.

  Identity is `(account, region)`: an account can light up Kura in as
  many regions as it needs, but only one server per region.

  Lifecycle:

      provisioning ⇄ failed
            ↓         ↑
            └→ active ┘
                      ↓
                  destroying → destroyed

  `status` is a **projection of observed cluster state**, not an
  independently-mutated state machine. Postgres owns intent (which
  region a server should exist in, the deployment history) and audit;
  the backing `KuraInstance` owns observed runtime state. Every
  reconciler tick re-derives `status` for present-intent servers from
  `(latest deployment intent, observed image, endpoint readiness)` and
  records the observation in `observed_image_tag` / `last_observed_at`.
  Nothing pins a sticky `:failed`: a failed
  deploy is recorded on the `kura_deployments` row (audit) and the
  server `status` is whatever the next projection derives, so infra
  recovery is reflected without an out-of-band retry. The deliberate
  exception is a previously-serving server whose newer rollout failed:
  it stays `:failed` while its old endpoint keeps serving, so traffic
  is never trampled, until the cluster converges on the intended image.
  See `Tuist.Kura.Reconciler`.

  `:failed` → `:provisioning` is the operator Retry path for a
  first-time deploy that never reached `:active`; the new deployment is
  appended to the same row so the failure history stays attached.
  `:destroyed` is reserved for operator-driven teardown.

  `url` and `current_image_tag` are populated when the server first
  reaches `:active` and updated on subsequent successful deployments.

  `provisioner_node_ref` is the opaque handle the provisioner returned
  from `provision/3`. The control plane stores it untouched and hands
  it back to the provisioner for `rollout/2` and `destroy/1`. For the
  Kubernetes controller provisioner it's the KuraInstance name.

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
    failed: [:failed, :provisioning, :active, :destroying],
    destroying: [:destroying, :destroyed],
    destroyed: [:destroyed]
  }
  @image_tag_format ~r/\A[A-Za-z0-9_][A-Za-z0-9_.-]*\z/
  @image_tag_message "must be a valid OCI image tag like sha-abcdef123456, latest, or 0.5.2"
  @provisioner_node_ref_format ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
  @provisioner_node_ref_message "must come from an account handle and region that produce a valid Kubernetes RFC1123 label"

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "kura_servers" do
    field :region, :string
    field :status, Ecto.Enum, values: @status_mappings, default: :provisioning
    field :url, :string
    field :current_image_tag, :string
    field :provisioner_node_ref, :string

    # Observed-state projection. Written only by the reconciler from the
    # backing KuraInstance, never by user actions: the image the cluster
    # reports running and when it was last successfully observed.
    field :observed_image_tag, :string
    field :last_observed_at, :utc_datetime

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
    |> validate_status_and_image()
  end

  @doc """
  Reconciler-only changeset for the observed-state projection. Casts
  the derived `status` alongside the observation columns and the
  activation outputs (`url`, `current_image_tag`). User-facing code
  never builds this changeset.
  """
  def observation_changeset(server, attrs) do
    server
    |> cast(attrs, [
      :status,
      :url,
      :current_image_tag,
      :observed_image_tag,
      :last_observed_at
    ])
    |> validate_format(:observed_image_tag, @image_tag_format, message: @image_tag_message)
    |> validate_length(:observed_image_tag, max: 128)
    |> validate_status_and_image()
  end

  defp validate_status_and_image(changeset) do
    changeset
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
