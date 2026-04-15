defmodule Tuist.FilterMemory do
  @moduledoc """
  Remembers the last-used query string per list route on a per-user, per-tab
  basis so that clicking a sidebar link returns the user to the view they had
  set up before navigating away.

  State is stored in the shared `:tuist` Cachex table as a single map per
  `{user_id, tab_id}`, with values shaped as `%{route_key => query_string}`.
  The tab id is supplied by the browser via LiveSocket connect params.
  """

  @cache :tuist
  @ttl to_timeout(hour: 4)

  def get_all(user_id, tab_id) when not is_nil(user_id) and is_binary(tab_id) and tab_id != "" do
    case Cachex.get(@cache, key(user_id, tab_id)) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  def get_all(_user_id, _tab_id), do: %{}

  def put(user_id, tab_id, route_key, query_string)
      when not is_nil(user_id) and is_binary(tab_id) and tab_id != "" and is_binary(route_key) do
    cache_key = key(user_id, tab_id)

    current =
      case Cachex.get(@cache, cache_key) do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    Cachex.put(@cache, cache_key, Map.put(current, route_key, query_string || ""), expire: @ttl)
    :ok
  end

  def put(_user_id, _tab_id, _route_key, _query_string), do: :ok

  defp key(user_id, tab_id), do: {:filter_memory, user_id, tab_id}
end
