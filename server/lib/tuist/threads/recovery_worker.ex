defmodule Tuist.Threads.RecoveryWorker do
  @moduledoc false
  use Oban.Worker, queue: :threads, max_attempts: 3

  @impl true
  def perform(_job), do: Tuist.Threads.recover()
end
