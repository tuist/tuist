defmodule TuistEx.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      %{id: GRPC.Client.Supervisor, start: {__MODULE__, :start_client, []}, type: :supervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: TuistEx.Cache.Reapi.Supervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: TuistEx.Supervisor)
  end

  def start_client do
    case DynamicSupervisor.start_link(GRPC.Client.Supervisor, [], name: GRPC.Client.Supervisor) do
      {:error, {:already_started, _pid}} -> :ignore
      other -> other
    end
  end
end
