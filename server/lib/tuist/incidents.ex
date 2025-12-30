defmodule Tuist.Incidents do
  @moduledoc ~S"""
  This module provides utilities obtain information about ongoing incidents.
  """
  use Retry

  alias Tuist.KeyValueStore

  def any_ongoing_incident?(opts \\ []) do
    KeyValueStore.get_or_update(
      [__MODULE__, "ongoing_incident"],
      [ttl: Keyword.get(opts, :ttl, to_timeout(minute: 1))],
      fn ->
        retry with: exponential_backoff() |> randomize() |> cap(1_000) |> expiry(10_000) do
          case Req.get("https://status.tuist.dev/proxy/status.tuist.dev", finch: Tuist.Finch) do
            {:ok, %{body: %{"summary" => %{"ongoing_incidents" => ongoing_incidents}}}} ->
              length(ongoing_incidents) > 0

            _ ->
              false
          end
        end
      end
    )
  end
end
