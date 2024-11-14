defmodule Tuist.Incidents do
  @moduledoc ~S"""
  This module provides utilities obtain information about ongoing incidents.
  """
  use Retry

  def any_ongoing_incident?(opts \\ []) do
    ttl = opts |> Keyword.get(:ttl, :timer.minutes(1))
    cache = Keyword.get(opts, :cache, :tuist)

    result =
      Cachex.fetch(cache, "ongoing_incident", fn ->
        active_incident? =
          retry with: exponential_backoff() |> randomize |> cap(1_000) |> expiry(10_000) do
            {:ok, %{body: body}} = Req.get("https://status.tuist.io/proxy/status.tuist.io")

            {:ok, %{"summary" => %{"ongoing_incidents" => ongoing_incidents}}} =
              Jason.decode(body)

            length(ongoing_incidents) > 0
          end

        {:commit, active_incident?, expire: ttl}
      end)

    case result do
      {:commit, active_incident?} ->
        active_incident?

      {:ok, active_incident?} ->
        active_incident?
    end
  end
end
