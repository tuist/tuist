defmodule Atlas.Briefs.Config do
  @moduledoc """
  Runtime configuration for briefs.

  Exists as a seam so code and tests read brief settings through a function
  rather than reaching into the application environment directly.
  """

  def leadership_slack_channel_id do
    case Application.get_env(:atlas, :briefs, [])[:leadership_slack_channel_id] do
      channel_id when is_binary(channel_id) and channel_id != "" -> channel_id
      _channel_id -> nil
    end
  end
end
