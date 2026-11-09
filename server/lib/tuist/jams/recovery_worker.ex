defmodule Tuist.Jams.RecoveryWorker do
  @moduledoc false
  use Oban.Worker, queue: :jams, max_attempts: 3

  @impl true
  def perform(_job), do: Tuist.Jams.recover()
end
