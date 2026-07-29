defmodule TuistWeb.Runs.CommandFormatter do
  @moduledoc false

  def format_command(%{name: name, command_arguments: command_arguments}) do
    case normalize_arguments(command_arguments) do
      "" -> "tuist #{name}"
      command_arguments -> "tuist #{command_arguments}"
    end
  end

  def normalize_command_filter_value(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/^tuist(?:\s+|$)/, "")
  end

  def normalize_command_filter_value(value), do: value

  defp normalize_arguments(nil), do: ""

  defp normalize_arguments(arguments) when is_binary(arguments), do: String.trim(arguments)

  defp normalize_arguments(arguments) when is_list(arguments) do
    arguments
    |> Enum.join(" ")
    |> String.trim()
  end

  defp normalize_arguments(_arguments), do: ""
end
