defmodule Atlas.Slack.AgentIdentities do
  @moduledoc """
  Slack binding resolution for generic Atlas agent identities.
  """

  import Ecto.Query

  alias Atlas.Agents.Identity
  alias Atlas.Agents.IdentityNormalization
  alias Atlas.Repo
  alias Atlas.Slack.AgentConfig
  alias Atlas.Slack.Bot
  alias Atlas.Slack.Channel

  def for_channel(app_key, channel) do
    case resolve_for_channel(app_key, channel) do
      %Identity{} = identity -> identity
      nil -> for_channel(app_key, channel, AgentConfig.identities())
    end
  end

  def configured_identities do
    Enum.map(AgentConfig.identities(), &from_configured_identity(&1, nil))
  end

  def for_channel(app_key, channel, configured_identities) when is_list(configured_identities) do
    app_key = normalize_app_key(app_key)

    configured_identities
    |> Enum.find(&configured_identity_matches?(&1, app_key, channel))
    |> case do
      nil -> Identity.default()
      configured_identity -> from_configured_identity(configured_identity, app_key)
    end
  end

  def resolve_for_channel(app_key, %Channel{} = channel) do
    app_key = normalize_app_key(app_key)

    Identity
    |> where([identity], identity.enabled == true)
    |> Repo.all()
    |> Enum.filter(&matches_channel?(&1, app_key, channel))
    |> Enum.sort_by(&sort_key(&1, channel))
    |> List.first()
  end

  def resolve_for_channel(_app_key, _channel), do: nil

  def matches_channel?(%Identity{} = identity, %Channel{} = channel) do
    matches_channel?(identity, channel.slack_app, channel)
  end

  def matches_channel?(%Identity{} = identity, app_key, %Channel{} = channel) do
    binding = slack_binding(identity)

    binding_app(binding) == normalize_app_key(app_key) and
      (binding_match_all_channels?(binding) or channel.channel_id in binding_channel_ids(binding))
  end

  def matches_channel?(_identity, _app_key, _channel), do: false

  def slack_bound?(%Identity{} = identity), do: slack_binding(identity) != %{}

  def slack_binding(%Identity{bindings: bindings}), do: slack_binding(bindings)

  def slack_binding(bindings) when is_map(bindings) do
    case Map.get(bindings, "slack") || Map.get(bindings, :slack) do
      binding when is_map(binding) -> binding
      _binding -> %{}
    end
  end

  def slack_binding(_bindings), do: %{}

  defp sort_key(identity, channel) do
    {match_rank(identity, channel), -identity.priority, identity.key}
  end

  defp match_rank(%Identity{} = identity, %Channel{} = channel) do
    binding = slack_binding(identity)

    cond do
      channel.channel_id in binding_channel_ids(binding) -> 0
      binding_match_all_channels?(binding) -> 1
      true -> 2
    end
  end

  defp configured_identity_matches?(identity, app_key, channel) do
    app_matches?(identity, app_key) and channel_matches?(identity, channel)
  end

  defp app_matches?(identity, app_key) do
    identity
    |> configured_slack_binding()
    |> binding_app()
    |> case do
      nil -> true
      configured_app -> configured_app == app_key
    end
  end

  defp channel_matches?(identity, %Channel{} = channel) do
    binding = configured_slack_binding(identity)
    channel_ids = binding_channel_ids(binding)

    channel.channel_id in channel_ids or binding_match_all_channels?(binding)
  end

  defp channel_matches?(_identity, _channel), do: false

  defp from_configured_identity(identity, app_key) do
    binding = configured_slack_binding(identity)
    configured_app = binding_app(binding) || app_key || :company
    channel_ids = binding_channel_ids(binding)
    tool_groups = configured_tool_groups(identity)
    tool_groups_by_agent = configured_tool_groups_by_agent(identity)

    %Identity{
      key:
        IdentityNormalization.normalize_key(
          config_value(identity, :key) || config_value(identity, :identity_key) || "default"
        ),
      display_name:
        normalize_display_name(
          config_value(identity, :display_name) ||
            config_value(identity, :identity_display_name) ||
            config_value(identity, :identity_name)
        ),
      enabled: true,
      priority: normalize_integer(config_value(identity, :priority)),
      bindings: %{
        "slack" => %{
          "app" => Atom.to_string(configured_app),
          "channel_ids" => channel_ids,
          "match_all_channels" => binding_match_all_channels?(binding)
        }
      },
      persona: normalize_persona(config_value(identity, :persona)),
      tool_groups: merge_tool_groups(tool_groups, tool_groups_by_agent),
      tool_groups_by_agent: tool_groups_by_agent,
      service_user_email: IdentityNormalization.normalize_string(config_value(identity, :service_user_email)),
      memory_scope: normalize_memory_scope(config_value(identity, :memory_scope)),
      requester_rules: IdentityNormalization.normalize_requester_rules(config_value(identity, :requester_rules)),
      metadata: %{}
    }
  end

  defp configured_slack_binding(identity) do
    identity
    |> config_value(:bindings)
    |> slack_binding()
    |> Map.merge(%{
      "app" => config_value(identity, :slack_app) || config_value(identity, :workspace),
      "channel_id" => config_value(identity, :channel_id),
      "channel_ids" => config_value(identity, :channel_ids),
      "channel_name" => config_value(identity, :channel_name),
      "match_all_channels" => config_value(identity, :match_all_channels)
    })
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp configured_tool_groups(identity) do
    (config_value(identity, :tool_groups) || config_value(identity, :mcp_tool_groups))
    |> IdentityNormalization.normalize_tool_groups()
  end

  defp configured_tool_groups_by_agent(identity) do
    (config_value(identity, :tool_groups_by_agent) ||
       config_value(identity, :agent_mcp_tool_groups) ||
       config_value(identity, :mcp_agent_tool_groups))
    |> IdentityNormalization.normalize_agent_tool_groups()
  end

  defp binding_app(binding) when is_map(binding) do
    (config_value(binding, :app) ||
       config_value(binding, :slack_app) ||
       config_value(binding, :workspace))
    |> normalize_app_key()
  end

  defp binding_app(_binding), do: nil

  defp binding_channel_ids(binding) when is_map(binding) do
    (config_value(binding, :channel_ids) || config_value(binding, :channel_id))
    |> normalize_channel_ids()
  end

  defp binding_channel_ids(_binding), do: []

  defp binding_match_all_channels?(binding) when is_map(binding) do
    config_value(binding, :match_all_channels) in [true, "true"]
  end

  defp binding_match_all_channels?(_binding), do: false

  defp config_value(identity, key) when is_map(identity) do
    cond do
      Map.has_key?(identity, key) -> Map.get(identity, key)
      Map.has_key?(identity, Atom.to_string(key)) -> Map.get(identity, Atom.to_string(key))
      true -> nil
    end
  end

  defp config_value(identity, key) when is_list(identity) do
    Keyword.get(identity, key)
  end

  defp config_value(_identity, _key), do: nil

  defp normalize_app_key(app_key) do
    case Bot.normalize_app_key(app_key) do
      {:ok, normalized} -> normalized
      :error -> nil
    end
  end

  defp normalize_persona(persona) when persona in [:leadership], do: persona
  defp normalize_persona("leadership"), do: :leadership
  defp normalize_persona(_persona), do: :default

  defp normalize_memory_scope(scope) when scope in [:global, :channel, :disabled], do: scope
  defp normalize_memory_scope("channel"), do: :channel
  defp normalize_memory_scope("disabled"), do: :disabled
  defp normalize_memory_scope(_scope), do: :global

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _parse_error -> 0
    end
  end

  defp normalize_integer(_value), do: 0

  defp normalize_display_name(name) do
    case IdentityNormalization.normalize_string(name) do
      nil -> "Atlas"
      name -> name
    end
  end

  defp normalize_channel_ids(channel_ids) when is_list(channel_ids) do
    channel_ids
    |> Enum.map(&IdentityNormalization.normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_channel_ids(channel_id) when is_binary(channel_id), do: normalize_channel_ids([channel_id])
  defp normalize_channel_ids(_channel_ids), do: []

  defp merge_tool_groups(tool_groups, tool_groups_by_agent) do
    agent_groups =
      tool_groups_by_agent
      |> Map.values()
      |> List.flatten()

    Enum.uniq(tool_groups ++ agent_groups)
  end
end
