defmodule TuistCommon.GitHub.RateLimit do
  @moduledoc """
  Holds the last rate-limit budget GitHub reported for each resource.

  GitHub only reports the budget on API responses, and the PromEx storage
  adapter flushes its tables on every scrape. A gauge emitted straight from
  the response would therefore only land in the scrape that happens to follow
  a GitHub call, and would vanish entirely while a worker backs off after
  being rate limited. Keeping the last observation here lets the PromEx
  plugin re-emit it on a schedule, so every scrape carries a sample.
  """
  use GenServer

  alias TuistCommon.GitHub

  @handler_id __MODULE__

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the last budget observed per resource, keyed by resource name.

  Returns an empty map when the tracker is not running so a scrape can never
  fail because of it.
  """
  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot)
  catch
    :exit, _reason -> %{}
  end

  @impl true
  def init(opts) do
    handler_id = Keyword.get(opts, :handler_id, @handler_id)

    :telemetry.attach(
      handler_id,
      GitHub.rate_limit_event_name(),
      &__MODULE__.handle_rate_limit_event/4,
      self()
    )

    {:ok, %{handler_id: handler_id, budgets: %{}}}
  end

  @impl true
  def terminate(_reason, %{handler_id: handler_id}) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_rate_limit_event(_event, measurements, metadata, server) do
    GenServer.cast(server, {:record, metadata.resource, measurements})
  end

  @impl true
  def handle_cast({:record, resource, measurements}, state) do
    {:noreply, %{state | budgets: Map.put(state.budgets, resource, measurements)}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.budgets, state}
  end
end
