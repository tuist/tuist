defmodule Atlas.TimeOff.SyncPublicHolidays do
  @moduledoc false

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 3600, states: :incomplete]

  alias Atlas.TimeOff

  @impl Oban.Worker
  def perform(_job) do
    case TimeOff.sync_public_holidays() do
      {:ok, _location} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
