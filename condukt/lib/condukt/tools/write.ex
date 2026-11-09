defmodule Condukt.Tools.Write do
  @moduledoc """
  Tool for writing content to files.

  Creates the file if it doesn't exist, overwrites if it does.
  Automatically creates parent directories as needed.

  All filesystem access goes through the active `Condukt.Sandbox`.

  ## Parameters

  - `path` - Path to the file to write
  - `content` - Content to write to the file
  """

  use Condukt.Tool

  alias Condukt.Sandbox

  @impl true
  def name, do: "Write"

  @impl true
  def description do
    """
    Write content to a file. Creates the file if it doesn't exist, overwrites if it does.
    Automatically creates parent directories.
    """
    |> String.trim()
  end

  @impl true
  def parameters do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Path to the file to write (relative or absolute)"
        },
        content: %{
          type: "string",
          description: "Content to write to the file"
        }
      },
      required: ["path", "content"]
    }
  end

  @impl true
  def call(%{"path" => path, "content" => content}, context) do
    sandbox = fetch_sandbox!(context)

    case Sandbox.write(sandbox, path, content) do
      :ok ->
        bytes = byte_size(content)
        lines = content |> String.split("\n") |> length()
        {:ok, "Wrote #{path} (#{lines} lines, #{bytes} bytes)"}

      {:error, reason} ->
        {:error, "Cannot write to #{path}: #{inspect(reason)}"}
    end
  end

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Write requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end
end
