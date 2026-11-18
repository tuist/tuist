defmodule Tuist.Entire.Workers.DeliveryWorker do
  @moduledoc false
  use Oban.Worker, queue: :webhooks, max_attempts: 10

  alias Tuist.Entire

  @impl Oban.Worker
  def perform(%Oban.Job{args: delivery}) do
    Entire.handle_delivery(delivery)
  end
end
