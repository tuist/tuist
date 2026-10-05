defmodule Tuist.MCP.Events.Queue do
  @moduledoc false

  alias Tuist.MCP.Events.JobKey
  alias Tuist.Repo

  def key(parts) do
    parts
    |> JSON.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  def enqueue(entries) do
    entries
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.chunk_every(100)
    |> Enum.reduce_while(:ok, fn batch, _acc ->
      case enqueue_batch(batch) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp enqueue_batch(entries) do
    result =
      Repo.transaction(fn ->
        now = DateTime.truncate(DateTime.utc_now(), :second)
        keys = Enum.map(entries, fn {key, _job} -> %{key: key, inserted_at: now} end)

        {_, inserted} = Repo.insert_all(JobKey, keys, on_conflict: :nothing, returning: [:key])
        new_keys = MapSet.new(inserted, & &1.key)

        jobs = for {key, job} <- entries, MapSet.member?(new_keys, key), do: job
        if jobs != [], do: Oban.insert_all(jobs)
      end)

    case result do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    reason ->
      if Repo.in_transaction?(), do: reraise(reason, __STACKTRACE__), else: {:error, reason}
  end
end
