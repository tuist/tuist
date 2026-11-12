defmodule Pulse.Test.RuntimeStatusServer do
  @moduledoc false
  use Pulse.Runtime.GenServer

  alias Pulse.Runtime.GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  @impl true
  def init(opts), do: {:ok, opts}
  @impl true
  def format_status(status), do: Map.put(status, :state, :redacted)
end
