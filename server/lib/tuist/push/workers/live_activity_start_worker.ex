defmodule Tuist.Push.Workers.LiveActivityStartWorker do
  @moduledoc "Drains pre-migration projection jobs; Luft now owns push-to-start."
  use Oban.Worker, queue: :push, max_attempts: 1

  @impl true
  def perform(_), do: {:cancel, :moved_to_luft}
end
