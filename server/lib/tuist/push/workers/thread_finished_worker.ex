defmodule Tuist.Push.Workers.ThreadFinishedWorker do
  @moduledoc "Drains pre-migration jobs without reading source conversations."
  use Oban.Worker, queue: :push, max_attempts: 1

  @impl true
  def perform(_), do: {:cancel, :moved_to_luft}
end
