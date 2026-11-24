defmodule LuftServer.Threads.RecoveryWorker do
  @moduledoc "Periodic repair and retention for Luft-owned durable execution."
  use Oban.Worker, queue: :threads, max_attempts: 3

  alias LuftServer.Agents.Purge
  alias LuftServer.Threads
  alias LuftServer.Threads.Runners

  @impl Oban.Worker
  def perform(_job) do
    Runners.delete_expired()
    Threads.recover()
    Purge.run()
  end
end
