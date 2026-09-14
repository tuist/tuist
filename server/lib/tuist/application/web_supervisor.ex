defmodule Tuist.Application.WebSupervisor do
  @moduledoc """
  Starts Oban before the endpoint, then starts its queues once Phoenix is ready.

  Reverse shutdown order lets Phoenix drain requests while Oban accepts inserts.
  Restarts repeat the startup sequence before accepting traffic and running jobs.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    oban = Keyword.fetch!(opts, :oban)
    config = Oban.Config.new(oban)

    start_queues =
      Supervisor.child_spec(
        {Task,
         fn ->
           for {queue, options} <- config.queues do
             :ok = Oban.start_queue(config.name, Keyword.merge(options, queue: queue, local_only: true))
           end
         end},
        restart: :transient
      )

    children = [
      {Oban, Keyword.put(oban, :queues, [])},
      Keyword.get(opts, :endpoint, TuistWeb.Endpoint),
      start_queues
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
