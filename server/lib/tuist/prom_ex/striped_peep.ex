defmodule Tuist.PromEx.StripedPeep do
  @moduledoc """
  "Striped" storage based on `PromEx.Storage.Peep`.
  """

  @behaviour PromEx.Storage

  @impl true
  def scrape(name) do
    metrics =
      name
      |> Peep.get_all_metrics()
      |> case do
        # Handle case when Peep instance doesn't exist
        nil -> %{}
        metrics -> metrics
      end

    flush_storage(name)

    metrics
    |> Peep.Prometheus.export()
    |> IO.iodata_to_binary()
  end

  defp flush_storage(name) do
    case Peep.Persistent.fetch(name) do
      %Peep.Persistent{storage: {Peep.Storage.Striped, tids}} ->
        tids
        |> Tuple.to_list()
        |> Enum.each(&:ets.delete_all_objects/1)

      _ ->
        :ok
    end
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
