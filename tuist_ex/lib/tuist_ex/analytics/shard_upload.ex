defmodule TuistEx.Analytics.ShardUpload do
  @moduledoc false

  # Each callback regenerates the part URL before PUT. Replaying a numbered
  # part is safe; initiating or completing an upload is deliberately outside
  # this retry loop. Keep at most four 64 MiB parts in flight.
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

  # Runs `request` up to three times, backing off between attempts, while it
  # fails with a network error or a status worth replaying. Shard builds
  # download through it too, so a storage blip does not fail a shard.
  @doc false
  def retry(request, sleep, attempt \\ 1) do
    result = request.()

    if attempt < 3 and retryable?(result) do
      sleep.(500 * attempt)
      retry(request, sleep, attempt + 1)
    else
      result
    end
  end

  defp retryable?({:error, {:http, status}}), do: status in [408, 429] or status >= 500
  defp retryable?({:error, {:http, status, _}}), do: status in [408, 429] or status >= 500
  defp retryable?({:error, :missing_etag}), do: false
  defp retryable?({:error, _}), do: true
  defp retryable?(_), do: false
end
