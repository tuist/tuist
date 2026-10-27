defmodule Atlas.Finance.Workers.SyncSource do
  @moduledoc """
  Synchronizes one configured finance source.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Atlas.Finance

  def perform(%Oban.Job{args: %{"source_key" => source_key}}) do
    case Finance.sync_source(source_key) do
      {:ok, _summary} -> :ok
      {:error, :source_not_configured} -> {:cancel, :source_not_configured}
      {:error, reason} -> {:error, reason}
    end
  end
end
