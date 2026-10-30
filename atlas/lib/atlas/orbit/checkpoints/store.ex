defmodule Atlas.Orbit.Checkpoints.Store do
  @moduledoc """
  Load-only `Condukt.SessionStore` that hands a restored snapshot to a new
  session. Saving is a no-op: checkpoints are written per turn by
  `Atlas.Orbit.Checkpoints`, fenced to the owning attempt.
  """
  @behaviour Condukt.SessionStore

  @impl true
  def load(opts) do
    case Keyword.get(opts, :snapshot) do
      nil -> :not_found
      snapshot -> {:ok, snapshot}
    end
  end

  @impl true
  def save(_snapshot, _opts), do: :ok

  @impl true
  def clear(_opts), do: :ok
end
