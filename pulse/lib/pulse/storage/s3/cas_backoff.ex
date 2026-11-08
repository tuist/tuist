defmodule Pulse.Storage.S3.CASBackoff do
  @moduledoc false

  # Maintenance is bounded best-effort work, not leader election. Jitter avoids
  # repeating the same read/write collision cadence against sustained ingest.
  def wait(attempts_remaining) when attempts_remaining in 2..5 do
    window = min(10 * Integer.pow(2, 5 - attempts_remaining), 200)
    :timer.sleep(:rand.uniform(window))
  end

  def wait(_), do: :ok
end
