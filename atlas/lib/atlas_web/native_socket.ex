defmodule AtlasWeb.NativeSocket do
  use Phoenix.Socket

  alias Atlas.Automations.Native
  alias Atlas.Guardian

  defmodule Credential do
    @moduledoc false
    @derive {Inspect, except: [:token]}
    defstruct [:token]
  end

  channel "execution:*", AtlasWeb.NativeExecutionChannel

  @impl true
  def connect(%{"run_id" => id}, socket, %{auth_token: token}) when is_binary(token) do
    with false <- Atlas.Demo.enabled?(),
         {:ok, actor, %{"typ" => "access_token"}} <- Guardian.resource_from_token(token),
         {:ok, _} <- Native.execution(actor, id) do
      {:ok, assign(socket, execution_id: id, credential: %Credential{token: token})}
    else
      _ -> :error
    end
  end

  def connect(_, _, _), do: :error
  @impl true
  def id(_), do: nil
end
