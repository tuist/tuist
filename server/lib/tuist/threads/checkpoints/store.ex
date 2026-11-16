defmodule Tuist.Threads.Checkpoints.Store do
  @moduledoc "Load-only Condukt store. Per-turn persistence is independently fenced by session ID."
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
