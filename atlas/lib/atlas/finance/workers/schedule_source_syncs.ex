defmodule Atlas.Finance.Workers.ScheduleSourceSyncs do
  @moduledoc """
  Enqueues one sync job per configured finance source.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Atlas.Finance
  alias Atlas.Finance.Workers.SyncSource

  def perform(%Oban.Job{}) do
    case Finance.configured_source_keys() do
      [] ->
        {:cancel, :source_not_configured}

      source_keys ->
        Enum.reduce_while(source_keys, {:ok, 0}, fn source_key, {:ok, count} ->
          source_key
          |> sync_job()
          |> Oban.insert()
          |> case do
            {:ok, _job} -> {:cont, {:ok, count + 1}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
    end
  end

  def sync_job(source_key) when is_binary(source_key) do
    SyncSource.new(
      %{source_key: source_key},
      unique: [
        period: {30, :minutes},
        fields: [:worker, :args],
        keys: [:source_key],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
  end
end
