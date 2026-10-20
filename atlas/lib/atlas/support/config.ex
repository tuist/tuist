defmodule Atlas.Support.Config do
  @moduledoc false

  def slack_channel_id, do: channel_id(:slack_channel_id)
  def slack_filtered_channel_id, do: channel_id(:slack_filtered_channel_id)

  defp channel_id(key) do
    case Application.get_env(:atlas, :support, [])[key] do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          value -> value
        end

      _value ->
        nil
    end
  end
end
