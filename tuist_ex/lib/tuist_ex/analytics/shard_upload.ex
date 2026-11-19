defmodule TuistEx.Analytics.ShardUpload do
  @moduledoc false

  @max_attempts 9

  # Each callback regenerates the part URL before PUT. Replaying a numbered
  # part is safe. Keep at most four 64 MiB parts in flight.
  def upload(chunks, upload_part, options \\ []) do
    sleep = Keyword.get(options, :sleep, &Process.sleep/1)

    chunks
    |> Stream.with_index(1)
    |> Task.async_stream(
      fn {chunk, number} ->
        with {:ok, etag} <- retry(fn -> upload_part.(chunk, number) end, sleep) do
          {:ok, %{part_number: number, etag: etag}}
        end
      end,
      max_concurrency: 4,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, part}}, {:ok, parts} -> {:cont, {:ok, [part | parts]}}
      {:ok, {:error, _} = error}, _ -> {:halt, error}
      {:exit, reason}, _ -> {:halt, {:error, {:upload_task_exit, reason}}}
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  # Runs `request` again while it fails with a network error or a status worth
  # replaying, backing off from half a second to 15 seconds between attempts.
  # The attempts span about a minute, so a restart of the shard store, during
  # which it refuses connections for some seconds, does not fail a shard.
  @doc false
  def retry(request, sleep, attempt \\ 1) do
    result = request.()

    if attempt < @max_attempts and retryable?(result) do
      sleep.(min(500 * Integer.pow(2, attempt - 1), 15_000))
      retry(request, sleep, attempt + 1)
    else
      result
    end
  end

  defp retryable?({:error, {:http, status}}), do: status in [408, 429] or status >= 500
  defp retryable?({:error, {:http, status, _}}), do: status in [408, 429] or status >= 500
  defp retryable?({:error, :missing_etag}), do: false
  # Configuration and authentication failures are messages; asking again
  # answers the same.
  defp retryable?({:error, reason}) when is_binary(reason), do: false
  defp retryable?({:error, _}), do: true
  defp retryable?(_), do: false
end
