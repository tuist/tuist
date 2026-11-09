defmodule Tuist.Sandboxes.DiskSnapshot do
  @moduledoc """
  A copy of a paused sandbox's rootfs and workspace disks, kept on the
  node that held the sandbox (`node_name`). New Amp Orbs of the same project
  are created from it instead of the template, so they skip the project's
  setup.

  `amp_snapshot_id` is the identifier Amp chooses (`ORB_SNAPSHOT_ID`); the
  row id names the copy on the node. A newer save under the same Amp
  identifier supersedes the older copies.

  Once ready, the copy is also uploaded to object storage (the `archive_*`
  fields, like a sandbox archive's) so any node can create a sandbox from
  it. An archived snapshot whose node copy is gone keeps its row with a
  nil `node_name`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.Sandbox

  @states [:saving, :ready]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandbox_disk_snapshots" do
    field :amp_snapshot_id, :string
    field :node_name, :string
    field :template, :string
    field :template_tag, :string
    field :workspace_gb, :integer
    field :state, Ecto.Enum, values: @states, default: :saving
    field :last_used_at, :utc_datetime
    field :archive_store, :string
    field :archive_key, :string
    field :archive_upload_id, :string
    field :archive_bytes, :integer
    field :archive_sha256, :string
    field :archived_at, :utc_datetime
    field :archive_attempted_at, :utc_datetime

    belongs_to :account, Account
    belongs_to :source_sandbox, Sandbox, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :account_id,
      :amp_snapshot_id,
      :source_sandbox_id,
      :node_name,
      :template,
      :template_tag,
      :workspace_gb,
      :last_used_at
    ])
    |> validate_required([:account_id, :amp_snapshot_id, :node_name, :template, :workspace_gb, :last_used_at])
    |> validate_length(:amp_snapshot_id, min: 1, max: 255)
  end

  def update_changeset(snapshot, attrs) do
    cast(snapshot, attrs, [
      :state,
      :last_used_at,
      :node_name,
      :archive_store,
      :archive_key,
      :archive_upload_id,
      :archive_bytes,
      :archive_sha256,
      :archived_at,
      :archive_attempted_at
    ])
  end
end
