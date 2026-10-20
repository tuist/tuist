defmodule Tuist.Application.EndpointDrainer do
  @moduledoc """
  Drains incoming traffic while retaining endpoint configuration for running jobs.
  """

  def drain(endpoint) do
    socket_drainers =
      for {_, socket, opts} <- Enum.uniq_by(endpoint.__sockets__(), &elem(&1, 1)),
          function_exported?(socket, :drainer_spec, 1),
          spec = socket.drainer_spec([endpoint: endpoint] ++ opts),
          spec != :ignore do
        Supervisor.child_spec(spec, []).id
      end

    # Match Phoenix's reverse shutdown order, but keep its configuration alive.
    for id <- Enum.reverse(socket_drainers, [{endpoint, :https}, {endpoint, :http}]) do
      case Supervisor.terminate_child(endpoint, id) do
        :ok -> :ok
        {:error, :not_found} -> :ok
      end
    end

    :ok
  end
end
