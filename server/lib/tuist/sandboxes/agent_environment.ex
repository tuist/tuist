defmodule Tuist.Sandboxes.AgentEnvironment do
  @moduledoc """
  An Anthropic self-hosted environment connected to an account, served
  with one sandbox per session from the template and shape stored here.
  `environment_key` is Cloak-encrypted at rest via `Tuist.Vault.Binary`.

  `kind` says which product the environment belongs to. A `:managed_agents`
  environment (`env_...`) is polled by the server with its environment key.
  A `:claude_code` environment (`ccpool_...`, a Claude Code cloud
  environment) stores its environment secret in `environment_key`; a
  provider workload runs its on-demand orchestrator, and each session's
  runner starts in the session's sandbox (`Tuist.Sandboxes.ClaudeCodeRunners`).
  Its `max_idle_seconds` is how long an idle session keeps its runner, and
  its optional `setup_script` makes a repository's sandboxes repo-ready: a
  builder sandbox runs it on the repository and saves the disks, and new
  sessions boot from that snapshot (`Tuist.Sandboxes.ClaudeCodeSnapshots`).

  `anthropic_api_key` (also Cloak-encrypted) is the organization API key
  the server uses to start sessions on the environment. Instead of a key, an
  environment can carry the four Workload Identity Federation ids
  (`anthropic_organization_id`, `anthropic_workspace_id`,
  `anthropic_service_account_id`, `anthropic_federation_rule_id`), all or
  none; the server then exchanges Tuist-signed tokens for short-lived ones
  (`Tuist.Sandboxes.Anthropic.Federation`). `anthropic_agent_id`
  caches the agent Tuist created for `agent_model` and `agent_system_prompt`;
  changing either clears the cache so the next session creates a new one.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Vault.Binary

  @derive {Inspect, except: [:environment_key, :anthropic_api_key]}
  schema "sandbox_agent_environments" do
    field :kind, Ecto.Enum, values: [:managed_agents, :claude_code], default: :managed_agents
    field :anthropic_environment_id, :string
    field :environment_key, Binary, redact: true
    field :anthropic_api_key, Binary, redact: true
    field :anthropic_organization_id, :string
    field :anthropic_workspace_id, :string
    field :anthropic_service_account_id, :string
    field :anthropic_federation_rule_id, :string
    field :anthropic_agent_id, :string
    field :agent_model, :string, default: "claude-sonnet-5"
    field :agent_system_prompt, :string
    field :setup_script, :string
    field :name, :string
    field :platform, Ecto.Enum, values: [:linux, :darwin], default: :linux
    field :template, :string, default: "default"
    field :vcpus, :integer, default: 2
    field :memory_mb, :integer, default: 4096
    field :workspace_gb, :integer, default: 10
    field :max_idle_seconds, :integer, default: 30
    field :pause_grace_seconds, :integer, default: 30
    field :enabled, :boolean, default: true

    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  @federation_fields [
    :anthropic_organization_id,
    :anthropic_workspace_id,
    :anthropic_service_account_id,
    :anthropic_federation_rule_id
  ]

  def federation_fields, do: @federation_fields

  # The script travels as one argument of the guest command, and Linux caps
  # a single argument at 128 KiB.
  @setup_script_max_bytes 65_536

  def create_changeset(agent_environment, attrs) do
    agent_environment
    |> cast(attrs, [
      :kind,
      :platform,
      :account_id,
      :anthropic_environment_id,
      :environment_key,
      :anthropic_api_key,
      :agent_model,
      :agent_system_prompt,
      :setup_script,
      :name,
      :anthropic_organization_id,
      :anthropic_workspace_id,
      :anthropic_service_account_id,
      :anthropic_federation_rule_id,
      :template,
      :vcpus,
      :memory_mb,
      :workspace_gb,
      :max_idle_seconds,
      :pause_grace_seconds,
      :enabled
    ])
    |> validate_required([:account_id, :anthropic_environment_id, :environment_key, :template, :agent_model])
    |> validate_length(:anthropic_environment_id, min: 1, max: 255)
    |> validate_environment_id()
    |> validate_length(:environment_key, min: 1)
    |> validate_agent_fields()
    |> validate_length(:name, max: 100)
    |> validate_format(:template, ~r/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/)
    |> Sandbox.validate_shape()
    |> validate_number(:max_idle_seconds, greater_than: 0, less_than_or_equal_to: 3600)
    |> validate_number(:pause_grace_seconds, greater_than_or_equal_to: 0, less_than_or_equal_to: 3600)
    |> unique_constraint(:anthropic_environment_id)
  end

  def update_changeset(agent_environment, attrs) do
    agent_environment
    |> cast(attrs, [:anthropic_api_key, :agent_model, :agent_system_prompt, :setup_script | @federation_fields])
    |> validate_required([:agent_model])
    |> validate_agent_fields()
    |> reset_cached_agent()
  end

  @doc """
  Validates the four federation ids on their own, all required, for the
  dashboard's connect flow, which checks them before the environment exists.
  """
  def federation_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @federation_fields)
    |> validate_required(@federation_fields)
    |> validate_federation_fields()
  end

  def cache_agent_changeset(agent_environment, anthropic_agent_id) do
    change(agent_environment, anthropic_agent_id: anthropic_agent_id)
  end

  # Claude Code names its environments `ccpool_...`, so one cannot be
  # connected as the other kind.
  defp validate_environment_id(changeset) do
    claude_code? = get_field(changeset, :kind) == :claude_code

    validate_change(changeset, :anthropic_environment_id, fn :anthropic_environment_id, id ->
      if String.starts_with?(id, "ccpool_") == claude_code?,
        do: [],
        else: [anthropic_environment_id: "does not name a #{get_field(changeset, :kind)} environment"]
    end)
  end

  defp validate_agent_fields(changeset) do
    changeset
    |> validate_length(:anthropic_api_key, min: 1)
    |> validate_length(:agent_model, min: 1, max: 255)
    |> validate_length(:agent_system_prompt, max: 100_000)
    |> validate_length(:setup_script, max: @setup_script_max_bytes, count: :bytes)
    |> validate_setup_script()
    |> validate_federation_fields()
  end

  # Only Claude Code runners start from a repository's snapshot, and only
  # Linux nodes save one.
  defp validate_setup_script(changeset) do
    if get_field(changeset, :setup_script) in [nil, ""] or
         (get_field(changeset, :kind) == :claude_code and get_field(changeset, :platform) == :linux),
       do: changeset,
       else: add_error(changeset, :setup_script, "is only supported by Linux Claude Code environments")
  end

  # The token exchange needs every id, so a partial set is rejected rather
  # than left to fail on the first session.
  defp validate_federation_fields(changeset) do
    changeset =
      if Enum.any?(@federation_fields, &get_field(changeset, &1)),
        do: validate_required(changeset, @federation_fields, message: "is required with the other federation ids"),
        else: changeset

    changeset
    |> validate_format(:anthropic_organization_id, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      message: "must be the organization's UUID"
    )
    |> validate_format(:anthropic_workspace_id, ~r/^wrkspc_[A-Za-z0-9_-]+$/, message: "must be a wrkspc_ id")
    |> validate_format(:anthropic_service_account_id, ~r/^svac_[A-Za-z0-9_-]+$/, message: "must be a svac_ id")
    |> validate_format(:anthropic_federation_rule_id, ~r/^fdrl_[A-Za-z0-9_-]+$/, message: "must be a fdrl_ id")
  end

  defp reset_cached_agent(changeset) do
    if changed?(changeset, :agent_model) or changed?(changeset, :agent_system_prompt) do
      put_change(changeset, :anthropic_agent_id, nil)
    else
      changeset
    end
  end
end
