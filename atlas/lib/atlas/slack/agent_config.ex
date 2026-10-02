defmodule Atlas.Slack.AgentConfig do
  @moduledoc """
  Runtime configuration for the Slack agent.
  """

  def mcp_user_email(default) when is_binary(default) do
    Keyword.get(config(), :mcp_user_email, default)
  end

  defp config, do: Application.get_env(:atlas, :slack_agent, [])
end
