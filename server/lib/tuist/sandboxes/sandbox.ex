defmodule Tuist.Sandboxes.Sandbox do
  @moduledoc """
  A Firecracker sandbox VM living on one sandboxd node. Created from a
  template snapshot, paused to the node's disk when idle, resumed when
  the next agent turn arrives.

  `residency_work_id` names the Anthropic work item whose worker is
  currently running inside the VM. `residency_epoch` increments every
  time a residency ends; the scheduled pause carries the epoch it was
  enqueued for and no-ops when a newer residency has started since.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.AgentEnvironment

  @states [:creating, :running, :resuming, :paused, :error, :deleted]
  # The shapes (vcpus, memory_mb) accounts can request. Each one costs a
  # template build and a memory image on every node that serves it, so the
  # list is short and matches the nodes' ALLOWED_SHAPES (chart
  # `sandboxes.allowedShapes`).
  @shapes [{2, 4096}, {4, 8192}, {8, 16_384}]
  @max_workspace_gb 100

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandboxes" do
    field :anthropic_session_id, :string
    field :template, :string
    field :template_tag, :string
    field :vcpus, :integer
    field :memory_mb, :integer
    field :workspace_gb, :integer
    field :state, Ecto.Enum, values: @states, default: :creating
    field :node_name, :string
    field :hostname, :string
    field :residency_work_id, :string
    field :residency_epoch, :integer, default: 0
    field :last_active_at, :utc_datetime
    field :paused_at, :utc_datetime
    field :error_message, :string

    belongs_to :account, Account
    belongs_to :agent_environment, AgentEnvironment

    timestamps(type: :utc_datetime)
  end

  def states, do: @states
  def shapes, do: @shapes
  def max_workspace_gb, do: @max_workspace_gb

  @doc """
  Validates `:vcpus` and `:memory_mb` against the offered shapes and caps
  `:workspace_gb`. Shared with agent environments, whose shape every
  sandbox of the environment takes.
  """
  def validate_shape(changeset) do
    vcpus = get_field(changeset, :vcpus)
    memory_mb = get_field(changeset, :memory_mb)

    changeset =
      if is_nil(vcpus) or is_nil(memory_mb) or {vcpus, memory_mb} in @shapes do
        changeset
      else
        offered = Enum.map_join(@shapes, ", ", fn {v, m} -> "#{v}x#{m}" end)
        add_error(changeset, :memory_mb, "vcpus x memory_mb must be one of #{offered}")
      end

    validate_number(changeset, :workspace_gb, greater_than: 0, less_than_or_equal_to: @max_workspace_gb)
  end

  def create_changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, [
      :account_id,
      :agent_environment_id,
      :anthropic_session_id,
      :template,
      :vcpus,
      :memory_mb,
      :workspace_gb
    ])
    |> validate_required([:account_id, :template, :vcpus, :memory_mb, :workspace_gb])
    |> validate_format(:template, ~r/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/)
    |> validate_shape()
    |> unique_constraint([:agent_environment_id, :anthropic_session_id])
  end

  def update_changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, [
      :template_tag,
      :state,
      :node_name,
      :hostname,
      :residency_work_id,
      :residency_epoch,
      :last_active_at,
      :paused_at,
      :error_message
    ])
    |> validate_required([:state])
  end
end
