defmodule ProcessorWeb.StatsController do
  use ProcessorWeb, :controller

  def show(conn, _params) do
    json(conn, %{in_flight: Processor.InFlight.count()})
  end
end
