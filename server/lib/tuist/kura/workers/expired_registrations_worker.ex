defmodule Tuist.Kura.Workers.ExpiredRegistrationsWorker do
  @moduledoc """
  Periodically deletes registered Kura endpoints whose lease has lapsed.

  Endpoint lookup already filters on the lease at query time, so this is pure
  housekeeping: it keeps the table and the registered-endpoint UI free of nodes
  that stopped heartbeating.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.Kura.Registrations

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Registrations.delete_expired() do
      0 -> :ok
      count -> Logger.info("[Kura.ExpiredRegistrationsWorker] swept #{count} expired registered endpoint(s)")
    end

    :ok
  end
end
