defmodule Pulse.Test.SelfMetricsStorage do
  @moduledoc false
  @behaviour Pulse.Storage

  @impl true
  def append(_signal, _tenant, _records, _opts), do: {:error, :unavailable}

  @impl true
  def query(_signal, _tenant, _opts), do: {:error, :unavailable}
end
