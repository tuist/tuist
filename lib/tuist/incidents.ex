defmodule Tuist.Incidents do
  @moduledoc ~S"""
  This module provides utilities obtain information about ongoing incidents.
  """
  use Nebulex.Caching.Decorators

  @decorate cacheable(cache: {Tuist.Cache, :tuist, []}, opts: [ttl: :timer.minutes(1)])
  def any_ongoing_incident?() do
    {:ok, %{body: body}} =
      Req.get("https://status.tuist.io/proxy/status.tuist.io")

    {:ok, %{"summary" => %{"ongoing_incidents" => ongoing_incidents}}} = Jason.decode(body)
    length(ongoing_incidents) > 0
  end
end
