defmodule Atlas.Slack.AgentConfig do
  @moduledoc """
  Runtime configuration for Slack agent identities and access.

  Keeping configuration access here gives the Slack domain a single boundary
  for the legacy channel-policy fallback and agent service-user settings.
  """

  def identities do
    config = config()

    case Keyword.get(config, :identities, []) do
      identities when is_list(identities) and identities != [] -> identities
      _identities -> Keyword.get(config, :channel_policies, [])
    end
  end

  def mcp_user_email(default) when is_binary(default) do
    Keyword.get(config(), :mcp_user_email, default)
  end

  defp config, do: Application.get_env(:atlas, :slack_agent, [])
end
