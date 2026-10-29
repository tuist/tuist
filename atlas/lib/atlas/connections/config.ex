defmodule Atlas.Connections.Config do
  @moduledoc false

  def credentials(provider) do
    :atlas |> Application.get_env(:account_connections, %{}) |> Map.get(provider, %{})
  end
end
