defmodule Tuist.Bazel.ProfileDecoder do
  @moduledoc "Bounds JSON containers while decoding, before constructing the complete profile."

  @max_entries 1_000_000
  @max_heap_bytes 64 * 1024 * 1024

  def decode(json) do
    {value, nil, rest} =
      JSON.decode(json, nil,
        array_start: &start/1,
        object_start: &start/1,
        array_push: &push/2,
        object_push: fn key, value, acc -> push({key, value}, acc) end,
        array_finish: fn acc, parent -> {Enum.reverse(acc.values), parent} end,
        object_finish: fn acc, parent -> {Map.new(acc.values), parent} end
      )

    if String.trim(rest) == "", do: {:ok, value}, else: {:error, :invalid_profile}
  rescue
    _ -> {:error, :invalid_profile}
  catch
    :profile_too_large -> {:error, :profile_too_large}
  end

  defp start(parent) do
    depth = if is_map(parent), do: parent.depth + 1, else: 1
    if depth > 64, do: throw(:profile_too_large)
    budget = if is_map(parent), do: parent.budget - parent.bytes, else: @max_heap_bytes
    %{depth: depth, count: 0, bytes: 0, budget: budget, values: []}
  end

  defp push(value, acc) do
    # Include off-heap binary contents as well as the decoded term's heap words.
    bytes = acc.bytes + :erts_debug.flat_size(value) * :erlang.system_info(:wordsize) + :erlang.external_size(value)
    if acc.count >= @max_entries or bytes > acc.budget, do: throw(:profile_too_large)
    %{acc | count: acc.count + 1, bytes: bytes, values: [value | acc.values]}
  end
end
