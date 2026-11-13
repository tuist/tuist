defmodule Condukt.Sandbox.Virtual.Tools.Mount do
  @moduledoc """
  Sandbox-specific tool for `Condukt.Sandbox.Virtual` that lets the agent
  mount a host directory into the virtual filesystem at runtime.

  This tool only makes sense with the Virtual sandbox. Routing through the
  generic `Condukt.Sandbox.mount/3` facade means it will return
  `{:error, :not_supported}` against `Sandbox.Local`, which is the correct
  behavior (the host filesystem is already the sandbox there, mounting would
  be meaningless).

  ## Parameters

  - `host_path` - Absolute path on the host filesystem
  - `vfs_path` - Absolute path inside the virtual filesystem to mount it at
  """

  use Condukt.Tool

  alias Condukt.Sandbox

  @impl true
  def name, do: "Mount"

  @impl true
  def description do
    """
    Mount a host directory into the virtual filesystem at the given path.
    Useful for letting the agent read or modify host project files from
    inside the virtual sandbox.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        host_path: %{
          type: "string",
          description: "Absolute path on the host filesystem"
        },
        vfs_path: %{
          type: "string",
          description: "Absolute path inside the virtual filesystem to mount at"
        }
      },
      required: ["host_path", "vfs_path"]
    }
  end

  @impl true
  def call(%{"host_path" => host_path, "vfs_path" => vfs_path}, %{sandbox: %Sandbox{} = sandbox}) do
    case Sandbox.mount(sandbox, host_path, vfs_path) do
      :ok ->
        {:ok, "Mounted #{host_path} at #{vfs_path}"}

      {:error, :not_supported} ->
        {:error, "The active sandbox does not support runtime mounting"}

      {:error, reason} ->
        {:error, "Mount failed: #{inspect(reason)}"}
    end
  end

  def call(_args, _context) do
    {:error, "Mount tool requires a sandbox-aware context"}
  end
end
