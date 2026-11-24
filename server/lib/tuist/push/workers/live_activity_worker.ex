defmodule Tuist.Push.Workers.LiveActivityWorker do
  @moduledoc "Drains pre-migration projection jobs; Luft now owns notification scheduling."
  use Oban.Worker, queue: :push, max_attempts: 1

  @impl true
  def perform(_), do: {:cancel, :moved_to_luft}
end
