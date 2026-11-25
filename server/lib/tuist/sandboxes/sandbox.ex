defmodule Tuist.Sandboxes.Sandbox do
  @moduledoc """
  A Firecracker sandbox VM living on one sandboxd node. Created from a
  template snapshot, paused to the node's disk when idle, resumed when
  the next agent turn arrives. An Amp Orb paused for long enough is
  `archived`: its disks move to object storage (`archive_*` fields), it has
  no node, and its next spawn restores it on any node
  (`Tuist.Sandboxes.Archives`).

  `residency_work_id` names the Anthropic work item whose worker is
  currently running inside the VM. `residency_epoch` increments every
  time a residency ends; the scheduled pause carries the epoch it was
  enqueued for and no-ops when a newer residency has started since.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.AgentEnvironment

  @states [:creating, :running, :resuming, :paused, :archived, :error, :deleted]
  # The shapes (vcpus, memory_mb) accounts can request. Each one costs a
  # template build and a memory image on every node that serves it, so the
  # list is short and matches the nodes' ALLOWED_SHAPES (chart
  # `sandboxes.allowedShapes`).
  @shapes [{1, 2048}, {2, 4096}, {4, 8192}, {8, 16_384}, {16, 32_768}, {16, 45_056}]
  @darwin_shapes [{8, 8192}, {8, 16_384}, {8, 24_576}]
  # A Linux agent sandbox boots with this many vCPUs whatever shape it asks
  # for: its shape picks the memory, and the guest bursts up to these vCPUs
  # into its node's idle cores. Its guarantee (`guaranteed_cpu_milli/1`) is
  # what it holds, and what it is billed when idle.
  @burst_vcpus 16
  # A Linux agent sandbox is guaranteed a vCPU per this much memory, the
  # hosts' own ratio (32 vCPUs to 128 GB), so the guarantees of the
  # sandboxes a host's memory holds never outgrow its cores.
  @mb_per_guaranteed_vcpu 4096
  # The guarantees a Linux agent sandbox's creator can pick above its
  # memory's, in millicores. A node's daemon can be guaranteed at most its
  # chart's `sandboxes.maxCpu`, so the largest stays well below it.
  @guaranteed_cpu_choices [1000, 2000, 4000, 8000]
  @max_workspace_gb 100
  # How long a sandbox created through the account API may run after each
  # create or resume (`lifetime_seconds`): two hours unless its creator asks
  # for between five minutes and a day, and extendable within the same range.
  @default_lifetime_seconds 7200
  @min_lifetime_seconds 300
  @max_lifetime_seconds 86_400

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "sandboxes" do
    field :purpose, Ecto.Enum, values: [:agent, :remote_execution], default: :agent
    # Renewed by the owning remote-execution scheduler; lapsed rows are reaped.
    field :execution_lease_expires_at, :utc_datetime
    field :anthropic_session_id, :string
    field :amp_orb_id, :string
    field :amp_base_snapshot_id, :string
    field :amp_snapshot_lineage_id, :string
    # The repository a Mac created through the account API was prepared
    # for, whose macOS snapshot it boots from or would have.
    field :repository, :string
    field :amp_creator_user_id, :string
    field :amp_creator_username, :string
    field :amp_creator_name, :string
    field :amp_creator_email, :string
    field :creator_actor, :map, virtual: true
    field :template, :string
    # The Xcode a create asked for, which picked `template`; not stored, the
    # template is what a macOS sandbox keeps (`Tuist.Sandboxes.Xcode`).
    field :xcode_version, :string, virtual: true
    field :template_tag, :string
    field :vcpus, :integer
    # The memory the sandbox is guaranteed (its request) and billed for at
    # least. A Linux agent sandbox with `memory_limit_mb` boots its guest
    # with that much instead and bursts into it (`boot_memory_mb/1`).
    field :memory_mb, :integer
    field :memory_limit_mb, :integer
    field :workspace_gb, :integer
    # NULL is the default guarantee (`guaranteed_cpu_milli/1`).
    field :guaranteed_cpu_milli, :integer
    field :state, Ecto.Enum, values: @states, default: :creating
    field :node_name, :string
    field :platform, Ecto.Enum, values: [:linux, :darwin], default: :linux
    field :node_uid, :string
    field :resident, :boolean, default: false
    field :hostname, :string
    field :residency_work_id, :string
    field :residency_epoch, :integer, default: 0
    field :last_active_at, :utc_datetime
    field :guest_cpu_ms, :integer
    # The VM's CPU time and when a report last billed it (`Sandboxes`'
    # metering); cleared with `guest_cpu_ms` when the sandbox pauses.
    field :metered_cpu_ms, :integer
    field :metered_at, :utc_datetime_usec
    field :paused_at, :utc_datetime
    field :error_message, :string
    # When a delete was asked for; kept on a row whose delete failed so a
    # create still in flight does not bring the sandbox back.
    field :delete_requested_at, :utc_datetime
    field :archive_key, :string
    field :archive_store, :string
    field :archive_upload_id, :string
    field :archive_bytes, :integer
    field :archive_sha256, :string
    # Set when the archive holds the memory image ahead of its disks:
    # `tail_offset` and `tail_sha256` locate the disk stream, `compat` is
    # the snapshot compatibility of nodes that can resume it warm, and
    # `loading_since` marks a warm restore still reading memory from it.
    field :archive_memory, :map
    field :archive_attempted_at, :utc_datetime
    field :archived_at, :utc_datetime
    # The runner cache volume and saved generation the sandbox's cache drive
    # was copied from at creation (`Tuist.Runners.CacheVolumes.sandbox_cache/2`).
    field :cache_volume_id, Ecto.UUID
    field :cache_generation, :integer
    # A sandbox created through the account API runs at most this long after
    # each create or resume, until `expires_at`; then it is paused and
    # archived (`Tuist.Sandboxes.pause_expired/0`). Integration-owned
    # sandboxes have neither and never expire.
    field :lifetime_seconds, :integer
    field :expires_at, :utc_datetime

    belongs_to :account, Account
    belongs_to :provider_environment, Tuist.Sandboxes.ProviderEnvironment, type: :binary_id
    belongs_to :amp_integration, Tuist.Sandboxes.AmpIntegration, type: :binary_id
    belongs_to :agent_environment, AgentEnvironment

    timestamps(type: :utc_datetime)
  end

  def states, do: @states
  def shapes, do: @shapes
  def shapes(:darwin), do: @darwin_shapes
  def shapes(_platform), do: @shapes
  def max_workspace_gb, do: @max_workspace_gb
  def burst_vcpus, do: @burst_vcpus
  def guaranteed_cpu_choices, do: @guaranteed_cpu_choices

  @doc """
  The memory a sandbox's guest boots with: its limit when it bursts above
  its request, otherwise its request. The node holds it at the request with
  the guest's balloon, which deflates when its processes need more.
  """
  def boot_memory_mb(%{memory_limit_mb: limit, memory_mb: request}) when is_integer(limit) and limit > request, do: limit

  def boot_memory_mb(%{memory_mb: memory_mb}), do: memory_mb

  @doc "The guest sizes a Linux agent sandbox can burst up to: the offered shapes' memory."
  def memory_limits, do: @shapes |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

  @doc """
  The CPU, in millicores, a sandbox (or an agent environment's shape) is
  guaranteed, and billed for at least, while it runs. A Linux agent sandbox
  bursts past it up to its vCPUs and is guaranteed a quarter vCPU per GiB of
  memory, or what its creator picked when that is more. A macOS sandbox,
  which cannot burst, holds every vCPU. A remote execution VM holds every
  vCPU of its shape, or, when it bursts (`RemoteExecution.Settings.boot_vcpus/2`),
  the shape's vCPUs it was reserved with. A node whose daemon runs each
  VM in its own cgroup holds it per sandbox; otherwise its sandboxes share
  their guarantees.
  """
  def guaranteed_cpu_milli(%{platform: :darwin, vcpus: vcpus}), do: vcpus * 1000

  def guaranteed_cpu_milli(%{purpose: :remote_execution, vcpus: vcpus} = sandbox),
    do: Map.get(sandbox, :guaranteed_cpu_milli) || vcpus * 1000

  def guaranteed_cpu_milli(%{memory_mb: memory_mb} = sandbox),
    do: max(Map.get(sandbox, :guaranteed_cpu_milli) || 0, memory_cpu_milli(memory_mb))

  defp memory_cpu_milli(memory_mb), do: div(memory_mb * 1000, @mb_per_guaranteed_vcpu)

  @doc "Millicores as vCPUs, whole when they are."
  def vcpus(milli) when rem(milli, 1000) == 0, do: div(milli, 1000)
  def vcpus(milli), do: milli / 1000

  @doc "Whether a Linux sandbox's creator picked more than its memory's guarantee, which only some nodes hold."
  def picked_guarantee?(sandbox),
    do: burst?(sandbox) and guaranteed_cpu_milli(sandbox) > memory_cpu_milli(sandbox.memory_mb)

  @doc "Whether the sandbox bursts past its guarantee: a Linux agent sandbox does."
  def burst?(%{platform: :darwin}), do: false
  def burst?(%{purpose: :remote_execution}), do: false
  def burst?(_sandbox), do: true

  @doc """
  Validates `:vcpus` and `:memory_mb` against the offered shapes and caps
  `:workspace_gb`. Shared with agent environments, whose shape every
  sandbox of the environment takes.
  """
  def validate_shape(changeset) do
    vcpus = get_field(changeset, :vcpus)
    memory_mb = get_field(changeset, :memory_mb)

    shapes = shapes(get_field(changeset, :platform))

    changeset =
      if is_nil(vcpus) or is_nil(memory_mb) or {vcpus, memory_mb} in shapes do
        changeset
      else
        offered = Enum.map_join(shapes, ", ", fn {v, m} -> "#{v}x#{m}" end)
        add_error(changeset, :memory_mb, "vcpus x memory_mb must be one of #{offered}")
      end

    validate_number(changeset, :workspace_gb, greater_than: 0, less_than_or_equal_to: @max_workspace_gb)
  end

  def create_changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, [
      :platform,
      :account_id,
      :purpose,
      :agent_environment_id,
      :anthropic_session_id,
      :amp_orb_id,
      :amp_base_snapshot_id,
      :amp_snapshot_lineage_id,
      :repository,
      :amp_integration_id,
      :provider_environment_id,
      :template,
      :xcode_version,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :guaranteed_cpu_milli,
      :memory_limit_mb,
      :lifetime_seconds
    ])
    |> validate_required([:account_id, :template, :vcpus, :memory_mb, :workspace_gb])
    |> validate_lifetime()
    |> validate_guaranteed_cpu()
    |> validate_memory_limit()
    |> validate_format(:template, ~r/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/)
    |> Tuist.Sandboxes.Xcode.validate()
    |> validate_shape()
    |> put_burst_vcpus()
    |> unique_constraint([:agent_environment_id, :anthropic_session_id])
    |> unique_constraint([:account_id, :amp_orb_id])
    |> unique_constraint(:provider_environment_id)
  end

  @doc """
  Sets the sandbox's lifetime and starts it now: it expires `seconds` from now.
  """
  def lifetime_changeset(sandbox, seconds) do
    sandbox
    |> cast(%{lifetime_seconds: seconds}, [:lifetime_seconds])
    |> validate_required([:lifetime_seconds])
    |> validate_lifetime()
  end

  def default_lifetime_seconds, do: @default_lifetime_seconds
  def max_lifetime_seconds, do: @max_lifetime_seconds

  defp validate_lifetime(changeset) do
    changeset =
      validate_number(changeset, :lifetime_seconds,
        greater_than_or_equal_to: @min_lifetime_seconds,
        less_than_or_equal_to: @max_lifetime_seconds
      )

    case get_field(changeset, :lifetime_seconds) do
      seconds when changeset.valid? and is_integer(seconds) ->
        expires_at = DateTime.utc_now() |> DateTime.add(seconds) |> DateTime.truncate(:second)
        put_change(changeset, :expires_at, expires_at)

      _ ->
        changeset
    end
  end

  # Only a Linux agent sandbox bursts, so only its guarantee is picked; a
  # macOS sandbox and a remote execution VM hold every vCPU.
  defp validate_guaranteed_cpu(changeset) do
    case get_field(changeset, :guaranteed_cpu_milli) do
      nil ->
        changeset

      _milli ->
        if get_field(changeset, :platform) == :darwin or get_field(changeset, :purpose) == :remote_execution,
          do: add_error(changeset, :guaranteed_cpu_milli, "only Linux sandboxes take a CPU guarantee"),
          else:
            validate_inclusion(changeset, :guaranteed_cpu_milli, @guaranteed_cpu_choices,
              message: "must be one of #{Enum.map_join(@guaranteed_cpu_choices, ", ", &vcpus/1)} vCPUs"
            )
    end
  end

  # Only a Linux agent sandbox bursts above its memory request, to one of
  # the offered guest sizes above it. A limit equal to the request is none.
  defp validate_memory_limit(changeset) do
    limit = get_field(changeset, :memory_limit_mb)
    request = get_field(changeset, :memory_mb)

    cond do
      is_nil(limit) ->
        changeset

      get_field(changeset, :platform) == :darwin or get_field(changeset, :purpose) == :remote_execution ->
        add_error(changeset, :memory_limit_mb, "only Linux sandboxes burst above their memory")

      limit == request ->
        put_change(changeset, :memory_limit_mb, nil)

      is_integer(request) and (limit < request or limit not in memory_limits()) ->
        offered = memory_limits() |> Enum.filter(&(&1 > request)) |> Enum.join(", ")
        add_error(changeset, :memory_limit_mb, "must be one of #{offered}")

      true ->
        changeset
    end
  end

  # Remote execution VMs keep their shape: their scheduler sizes actions
  # against it.
  defp put_burst_vcpus(%Ecto.Changeset{valid?: true} = changeset) do
    if get_field(changeset, :platform) == :darwin or get_field(changeset, :purpose) == :remote_execution,
      do: changeset,
      else: put_change(changeset, :vcpus, @burst_vcpus)
  end

  defp put_burst_vcpus(changeset), do: changeset

  def update_changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, [
      :template_tag,
      :state,
      :node_name,
      :node_uid,
      :resident,
      :hostname,
      :residency_work_id,
      :residency_epoch,
      :last_active_at,
      :guest_cpu_ms,
      :paused_at,
      :error_message,
      :delete_requested_at,
      :archive_key,
      :archive_store,
      :archive_upload_id,
      :archive_bytes,
      :archive_sha256,
      :archive_memory,
      :archive_attempted_at,
      :archived_at,
      :cache_volume_id,
      :cache_generation
    ])
    |> validate_required([:state])
  end
end
