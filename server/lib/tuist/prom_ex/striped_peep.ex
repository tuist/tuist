defmodule Tuist.PromEx.StripedPeep do
  @moduledoc """
  `PromEx` storage backed by `Peep`'s striped tables, which give each
  scheduler its own ETS table instead of contending on a shared one.

  Scrapes are non-destructive, so counters and distributions are cumulative
  across the life of the node. Prometheus requires that: `rate/1` and
  `histogram_quantile/2` need a sample on every scrape, and a metric whose
  storage is emptied disappears from the export entirely whenever no event
  lands between two scrapes. `PromEx` also drives `scrape/1` from
  `PromEx.ETSCronFlusher` on a timer and throws the result away, so anything
  freed on read is freed without ever reaching the scraper.

  Memory is therefore bounded by tag cardinality rather than by uptime. Every
  metric registered by the plugins in `Tuist.PromEx` tags on a closed set
  (queue, state, worker, fleet, request host, ...), and `Tuist.PromEx.Buckets`
  gives each distribution a fixed bucket list.
  """

  @behaviour PromEx.Storage

  @impl true
  def scrape(name) do
    name
    |> Peep.get_all_metrics()
    |> case do
      nil -> %{}
      metrics -> metrics
    end
    |> Peep.Prometheus.export()
    |> IO.iodata_to_binary()
  end

  @impl true
  def child_spec(name, metrics) do
    opts = [
      name: name,
      metrics: metrics,
      storage: :striped
    ]

    Peep.child_spec(opts)
  end
end
