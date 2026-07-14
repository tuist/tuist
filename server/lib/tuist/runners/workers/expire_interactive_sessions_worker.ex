defmodule Tuist.Runners.Workers.ExpireInteractiveSessionsWorker do
  @moduledoc """
  Closes interactive runner sessions whose hard TTL has elapsed.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Tuist.Runners.InteractiveSessions

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    {:ok, count} = InteractiveSessions.close_expired()

    if count > 0 do
      Logger.info("runners: expired interactive sessions", count: count)
    end

    :ok
  end
end
