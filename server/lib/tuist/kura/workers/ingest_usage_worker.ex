defmodule Tuist.Kura.Workers.IngestUsageWorker do
  @moduledoc """
  Delivers accepted Kura usage batches to ClickHouse. The dedicated queue
  bounds write concurrency per server node; failed batches follow Oban's
  retry and pruning lifecycle. Resolved account/project ids and timestamps
  remain fixed across retries; usage queries deduplicate by event_id.
  """

  use Oban.Worker, queue: :kura_usage, max_attempts: 20

  alias Tuist.IngestRepo
  alias Tuist.Kura.UsageEvent

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"rows" => rows}}) do
    fields = UsageEvent.__schema__(:fields)

    rows =
      Enum.map(rows, fn row ->
        UsageEvent
        |> Ecto.embedded_load(row, :json)
        |> Map.take(fields)
      end)

    IngestRepo.insert_all(UsageEvent, rows)
    :ok
  end
end
