defmodule Tuist.Incidents do
  @moduledoc ~S"""
  This module provides utilities obtain information about ongoing incidents.
  """
  use Retry
  require Logger

  def any_ongoing_incident?(opts \\ []) do
    ttl = opts |> Keyword.get(:ttl, :timer.minutes(1))
    cache = Keyword.get(opts, :cache, :tuist)

    result =
      Cachex.fetch(cache, "ongoing_incident", fn ->
        active_incident? =
          retry with: exponential_backoff() |> randomize |> cap(1_000) |> expiry(10_000) do
            {:ok, %{body: body}} = Req.get("https://status.tuist.dev/proxy/status.tuist.dev")
            %{"summary" => %{"ongoing_incidents" => ongoing_incidents}} = body

            length(ongoing_incidents) > 0
          end

        {:commit, active_incident?, expire: ttl}
      end)

    case result do
      {:commit, active_incident?} ->
        active_incident?

      {:ok, active_incident?} ->
        active_incident?

      {:error, error} ->
        Logger.error("Error while fetching ongoing incidents: #{inspect(error)}")
        false
    end
  end
end
