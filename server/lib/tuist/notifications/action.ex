defmodule Tuist.Notifications.Action do
  @moduledoc """
  What a notification rule does when it matches. Each action is a map with a
  `type`; a rule has at least one and at most one of each type.

  - `push`: a notification on each of the user's devices registered with
    `Tuist.Push`.

  To add a type (email, for example), add it to `@types`, validate its options
  in `cast/1`, and deliver it in the event's sender.
  """

  @types %{"push" => "Send a notification to the user's Tuist app devices."}

  def types, do: @types

  def cast_all(actions) when is_list(actions) and actions != [] do
    with {:ok, actions} <- cast_each(actions) do
      types = Enum.map(actions, & &1["type"])
      if Enum.uniq(types) == types, do: {:ok, actions}, else: {:error, "can't repeat an action type"}
    end
  end

  def cast_all(_actions), do: {:error, "must list at least one action"}

  defp cast_each(actions) do
    Enum.reduce_while(actions, {:ok, []}, fn action, {:ok, acc} ->
      case cast(action) do
        {:ok, action} -> {:cont, {:ok, acc ++ [action]}}
        {:error, _message} = error -> {:halt, error}
      end
    end)
  end

  defp cast(action) when is_map(action) do
    case Map.new(action, fn {key, value} -> {to_string(key), value} end) do
      %{"type" => "push"} = push when map_size(push) == 1 -> {:ok, %{"type" => "push"}}
      %{"type" => type} when is_map_key(@types, type) -> {:error, "#{type} actions take no options"}
      _ -> {:error, "types must be one of: #{@types |> Map.keys() |> Enum.join(", ")}"}
    end
  end

  defp cast(_action), do: {:error, "must be objects"}
end
