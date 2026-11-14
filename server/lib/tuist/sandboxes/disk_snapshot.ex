defmodule Tuist.Sandboxes.DiskSnapshot do
  @moduledoc """
  A copy of a paused sandbox's rootfs and workspace disks, kept on the
  node that held the sandbox (`node_name`). New Amp Orbs of the same project
  are created from it instead of the template, so they skip the project's
  setup.

  `amp_snapshot_id` is the identifier Amp chooses (`ORB_SNAPSHOT_ID`); the
  row id names the copy on the node. A newer save under the same Amp
  identifier supersedes the older copies.

  A Claude Code repository snapshot has no Amp identifier: it is keyed by
  its `agent_environment`, `repository` (`owner/name`) and the SHA-256 of
  the environment's setup script it ran (`Tuist.Sandboxes.ClaudeCodeSnapshots`).
  Its build is a row of that key in state `building`, with no node and the
  same id as its builder sandbox, which becomes `failed` when the build
  fails; at most one of either exists per key.

  Once ready, the copy is also uploaded to object storage (the `archive_*`
  fields, like a sandbox archive's) so any node can create a sandbox from
  it. An archived snapshot whose node copy is gone keeps its row with a
  nil `node_name`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Sandbox

  @states [:building, :failed, :saving, :ready]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandbox_disk_snapshots" do
    field :amp_snapshot_id, :string
    field :lineage_id, :string
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
    field :repository, :string
    field :setup_sha256, :string

    belongs_to :account, Account
    belongs_to :source_sandbox, Sandbox, type: :binary_id
    belongs_to :agent_environment, AgentEnvironment

    timestamps(type: :utc_datetime)
  end

  def create_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :account_id,
      :amp_snapshot_id,
      :lineage_id,
      :source_sandbox_id,
      :node_name,
      :template,
      :template_tag,
      :workspace_gb,
      :last_used_at,
      :agent_environment_id,
      :repository,
      :setup_sha256
    ])
    |> validate_required([:account_id, :node_name, :template, :workspace_gb, :last_used_at])
    |> validate_key()
  end

  # Amp names its snapshots; a Claude Code snapshot is named by its
  # environment, repository and setup script instead.
  defp validate_key(changeset) do
    if get_field(changeset, :agent_environment_id) do
      validate_required(changeset, [:repository, :setup_sha256])
    else
      changeset
      |> validate_required([:amp_snapshot_id])
      |> validate_length(:amp_snapshot_id, min: 1, max: 255)
    end
  end

  def build_changeset(attrs) do
    %__MODULE__{state: :building}
    |> cast(attrs, [
      :account_id,
      :agent_environment_id,
      :repository,
      :setup_sha256,
      :template,
      :workspace_gb,
      :last_used_at
    ])
    |> validate_required([
      :account_id,
      :agent_environment_id,
      :repository,
      :setup_sha256,
      :template,
      :workspace_gb,
      :last_used_at
    ])
    |> unique_constraint([:agent_environment_id, :repository, :setup_sha256],
      name: :sandbox_disk_snapshots_repository_build_index
    )
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
