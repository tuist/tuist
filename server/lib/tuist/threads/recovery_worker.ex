defmodule Tuist.Threads.RecoveryWorker do
  @moduledoc false
  use Oban.Worker, queue: :threads, max_attempts: 3

  alias Tuist.Threads.Runners

  @impl true
  def perform(_job) do
    Runners.delete_expired()
    Tuist.Threads.recover()
  end
end
