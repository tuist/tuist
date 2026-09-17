defmodule Atlas.Agents.Identity do
  @moduledoc """
  A persisted Atlas agent identity.

  Identities describe how an Atlas agent should operate: persona, service
  user, tool grants, memory behavior, requester authorization rules, and
  provider bindings such as Slack channel routing.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Agents.IdentityNormalization

  @personas [:default, :leadership]
  @memory_scopes [:global, :channel, :disabled]
  @known_agents [:conversation, :systems_investigator]
  @direct_agent_tool_groups ["finance", "documents"]

  schema "agent_identities" do
    field :key, :string
    field :display_name, :string
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 0
    field :bindings, :map, default: %{}

    field :persona, Ecto.Enum, values: @personas, default: :default
    field :tool_groups, {:array, :string}, default: []
    field :tool_groups_by_agent, :map, default: %{}
    field :service_user_email, :string
    field :memory_scope, Ecto.Enum, values: @memory_scopes, default: :global
    field :requester_rules, :map, default: %{}
    field :metadata, :map, default: %{}

    timestamps()
  end

  def personas, do: @personas
  def memory_scopes, do: @memory_scopes

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :key,
      :display_name,
      :enabled,
      :priority,
      :bindings,
      :persona,
      :tool_groups,
      :tool_groups_by_agent,
      :service_user_email,
      :memory_scope,
      :requester_rules,
      :metadata
    ])
    |> validate_required([
      :key,
      :display_name,
      :enabled,
      :priority,
      :bindings,
      :persona,
      :tool_groups,
      :tool_groups_by_agent,
      :memory_scope,
      :requester_rules,
      :metadata
    ])
    |> update_change(:key, &IdentityNormalization.normalize_key/1)
    |> validate_format(:key, ~r/^[a-z0-9][a-z0-9_-]*$/)
    |> update_change(:bindings, &IdentityNormalization.normalize_bindings/1)
    |> update_change(:tool_groups, &IdentityNormalization.normalize_tool_groups/1)
    |> update_change(:tool_groups_by_agent, &normalize_agent_tool_groups/1)
    |> update_change(:requester_rules, &IdentityNormalization.normalize_requester_rules/1)
    |> unique_constraint(:key)
  end

  def default do
    %__MODULE__{
      key: "default",
      display_name: "Atlas",
      enabled: true,
      priority: 0,
      bindings: %{},
      persona: :default,
      tool_groups: [],
      tool_groups_by_agent: empty_agent_tool_groups(),
      memory_scope: :global,
      requester_rules: %{},
      metadata: %{}
    }
  end

  def persona_instructions(%__MODULE__{persona: :leadership}) do
    """
    Channel persona:
    - Act as a leadership operator.
    - Be candid about tradeoffs, risks, urgency, and company impact.
    - When finance data is available, connect it to runway, revenue quality,
      cash timing, and operating decisions.
    - When a question touches contracts, invoices, board materials, or other
      financial paperwork, look it up with the document tools and surface the
      relevant documents. Always include each document's url so leadership can
      open the original file in one click.
    """
  end

  def persona_instructions(%__MODULE__{}), do: nil

  def tool_groups_for_agent(%__MODULE__{} = identity, agent) when agent in @known_agents do
    identity
    |> normalized_tool_groups_by_agent()
    |> Map.get(Atom.to_string(agent), [])
  end

  def all_tool_groups(%__MODULE__{} = identity) do
    agent_groups =
      identity
      |> normalized_tool_groups_by_agent()
      |> Map.values()
      |> List.flatten()

    Enum.uniq(IdentityNormalization.normalize_tool_groups(identity.tool_groups) ++ agent_groups)
  end

  defp normalize_agent_tool_groups(groups), do: normalize_agent_tool_groups(groups, [])

  defp normalize_agent_tool_groups(nil, tool_groups) do
    conversation_groups = Enum.filter(tool_groups, &(&1 in @direct_agent_tool_groups))

    %{
      "conversation" => conversation_groups,
      "systems_investigator" => tool_groups -- conversation_groups
    }
  end

  defp normalize_agent_tool_groups(groups, _tool_groups) when is_map(groups) and map_size(groups) == 0, do: %{}

  defp normalize_agent_tool_groups(groups, _tool_groups) when is_map(groups) do
    IdentityNormalization.normalize_agent_tool_groups(groups, @known_agents)
  end

  defp normalize_agent_tool_groups(groups, tool_groups) when is_list(groups) do
    normalize_agent_tool_groups(Map.new(groups), tool_groups)
  end

  defp normalize_agent_tool_groups(_groups, tool_groups), do: normalize_agent_tool_groups(nil, tool_groups)

  defp normalized_tool_groups_by_agent(%__MODULE__{} = identity) do
    case identity.tool_groups_by_agent || %{} do
      empty when empty == %{} ->
        normalize_agent_tool_groups(nil, IdentityNormalization.normalize_tool_groups(identity.tool_groups))

      groups ->
        normalize_agent_tool_groups(groups, IdentityNormalization.normalize_tool_groups(identity.tool_groups))
    end
  end

  defp empty_agent_tool_groups do
    %{
      "conversation" => [],
      "systems_investigator" => []
    }
  end
end
