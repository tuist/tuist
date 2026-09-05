defmodule Tuist.OpenGraphImageRetention do
  @moduledoc """
  Removes generated Open Graph images after their cache lifetime.

  The images are derivatives and are regenerated on demand, so a bounded
  retention window prevents frequently changing project metrics from growing
  object storage indefinitely.
  """

  alias Tuist.Storage

  @actor :open_graph_images
  @prefix "open-graph-images/"
  @default_retention_days 30
  @default_page_size 1_000

  def delete_expired(opts \\ []) do
    retention_days = Keyword.get(opts, :retention_days, @default_retention_days)
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    continuation_token = Keyword.get(opts, :continuation_token)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    cutoff = DateTime.add(now, -retention_days, :day)

    with {:ok, %{body: body}} <-
           Storage.list_objects(@prefix, @actor,
             max_keys: page_size,
             continuation_token: continuation_token
           ),
         :ok <- delete_expired_objects(Map.get(body, :contents, []), cutoff) do
      {:ok, next_continuation_token(body)}
    end
  end

  defp delete_expired_objects(objects, cutoff) do
    object_keys =
      objects
      |> Enum.filter(&expired?(&1, cutoff))
      |> Enum.map(& &1.key)

    Storage.delete_objects(object_keys, @actor)
  end

  defp expired?(%{last_modified: %DateTime{} = last_modified}, cutoff) do
    DateTime.before?(last_modified, cutoff)
  end

  defp expired?(%{last_modified: last_modified}, cutoff) when is_binary(last_modified) do
    case DateTime.from_iso8601(last_modified) do
      {:ok, datetime, _offset} -> DateTime.before?(datetime, cutoff)
      {:error, _reason} -> false
    end
  end

  defp expired?(_object, _cutoff), do: false

  defp next_continuation_token(body) do
    if Map.get(body, :is_truncated) in [true, "true"] do
      Map.get(body, :next_continuation_token)
    end
  end
end
