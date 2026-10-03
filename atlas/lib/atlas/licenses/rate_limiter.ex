defmodule Atlas.Licenses.RateLimiter do
  @moduledoc """
  Bounds online validation attempts per opaque client or license identifier and time window.

  The in-memory bucket store is deliberately bounded. It protects the public
  validation endpoint and its audit trail without retaining raw license keys.
  The window arithmetic itself lives in `Atlas.Licenses.RateLimiter.Buckets`;
  this process only owns the store and the configured limits.
  """

  use GenServer

  alias Atlas.Licenses.RateLimiter.Buckets

  @default_max_attempts 60
  @default_window_milliseconds :timer.minutes(1)
  @default_max_buckets 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, name: Keyword.get(opts, :name, __MODULE__))
  end

  def check(identifier) when is_binary(identifier) do
    GenServer.call(__MODULE__, {:check, identifier})
  end

  @impl true
  def init(_state) do
    schedule_cleanup()
    {:ok, Buckets.new()}
  end

  @impl true
  def handle_call({:check, identifier}, _from, buckets) do
    now = System.monotonic_time(:millisecond)

    case Buckets.check(buckets, identifier, now, limits()) do
      {:ok, buckets} -> {:reply, :ok, buckets}
      {{:error, retry_after_seconds}, buckets} -> {:reply, {:error, retry_after_seconds}, buckets}
    end
  end

  @impl true
  def handle_info(:cleanup, buckets) do
    schedule_cleanup()
    {:noreply, Buckets.prune(buckets, System.monotonic_time(:millisecond), limits().window_milliseconds)}
  end

  defp limits do
    config = Application.get_env(:atlas, __MODULE__, [])

    %{
      max_attempts: positive_integer(config[:max_attempts], @default_max_attempts),
      window_milliseconds: positive_integer(config[:window_milliseconds], @default_window_milliseconds),
      max_buckets: positive_integer(config[:max_buckets], @default_max_buckets)
    }
  end

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @default_window_milliseconds)
  end
end
