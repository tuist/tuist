defmodule Tuist.Sandboxes.AgentEnvironment do
  @moduledoc """
  An Anthropic Managed Agents `self_hosted` environment connected to an
  account. The server polls the environment's work queue with
  `environment_key` (Cloak-encrypted at rest via `Tuist.Vault.Binary`)
  and creates one sandbox per session from the template and shape stored
  here.

  `anthropic_api_key` (also Cloak-encrypted) is the organization API key
  the server uses to start sessions on the environment. `anthropic_agent_id`
  caches the agent Tuist created for `agent_model` and `agent_system_prompt`;
  changing either clears the cache so the next session creates a new one.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Vault.Binary

  @derive {Inspect, except: [:environment_key, :anthropic_api_key]}
  schema "sandbox_agent_environments" do
    field :anthropic_environment_id, :string
    field :environment_key, Binary, redact: true
    field :anthropic_api_key, Binary, redact: true
    field :anthropic_agent_id, :string
    field :agent_model, :string, default: "claude-sonnet-5"
    field :agent_system_prompt, :string
    field :name, :string
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

  def create_changeset(agent_environment, attrs) do
    agent_environment
    |> cast(attrs, [
      :account_id,
      :anthropic_environment_id,
      :environment_key,
      :anthropic_api_key,
      :agent_model,
      :agent_system_prompt,
      :name,
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
    |> validate_length(:environment_key, min: 1)
    |> validate_agent_fields()
    |> validate_length(:name, max: 100)
    |> validate_format(:template, ~r/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/)
    |> validate_number(:vcpus, greater_than: 0, less_than_or_equal_to: 64)
    |> validate_number(:memory_mb, greater_than_or_equal_to: 256, less_than_or_equal_to: 262_144)
    |> validate_number(:workspace_gb, greater_than: 0, less_than_or_equal_to: 1024)
    |> validate_number(:max_idle_seconds, greater_than: 0, less_than_or_equal_to: 3600)
    |> validate_number(:pause_grace_seconds, greater_than_or_equal_to: 0, less_than_or_equal_to: 3600)
    |> unique_constraint(:anthropic_environment_id)
  end

  def update_changeset(agent_environment, attrs) do
    agent_environment
    |> cast(attrs, [:anthropic_api_key, :agent_model, :agent_system_prompt])
    |> validate_required([:agent_model])
    |> validate_agent_fields()
    |> reset_cached_agent()
  end

  def cache_agent_changeset(agent_environment, anthropic_agent_id) do
    change(agent_environment, anthropic_agent_id: anthropic_agent_id)
  end

  defp validate_agent_fields(changeset) do
    changeset
    |> validate_length(:anthropic_api_key, min: 1)
    |> validate_length(:agent_model, min: 1, max: 255)
    |> validate_length(:agent_system_prompt, max: 100_000)
  end

  defp reset_cached_agent(changeset) do
    if changed?(changeset, :agent_model) or changed?(changeset, :agent_system_prompt) do
      put_change(changeset, :anthropic_agent_id, nil)
    else
      changeset
    end
  end
end
