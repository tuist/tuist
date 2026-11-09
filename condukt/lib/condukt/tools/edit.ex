defmodule Condukt.Tools.Edit do
  @moduledoc """
  Tool for making surgical edits to files.

  Finds exact text in a file and replaces it with new text.
  The old_text must match exactly, including whitespace.

  All filesystem access goes through the active `Condukt.Sandbox`.

  ## Parameters

  - `path` - Path to the file to edit
  - `old_text` - Exact text to find and replace (must match exactly)
  - `new_text` - New text to replace the old text with

  ## Notes

  - The match is exact and case-sensitive
  - Whitespace and indentation must match exactly
  - The target text must appear exactly once
  - For multiple replacements, provide more context to make each match unique
  """

  use Condukt.Tool

  alias Condukt.Sandbox

  @impl true
  def name, do: "Edit"

  @impl true
  def description do
    """
    Edit a file by replacing exact text. The old_text must match exactly (including whitespace).
    Use this for precise, surgical edits.
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
          description: "Path to the file to edit (relative or absolute)"
        },
        old_text: %{
          type: "string",
          description: "Exact text to find and replace (must match exactly)"
        },
        new_text: %{
          type: "string",
          description: "New text to replace the old text with"
        }
      },
      required: ["path", "old_text", "new_text"]
    }
  end

  @impl true
  def call(%{"path" => path, "old_text" => old_text, "new_text" => new_text}, _context) when old_text == new_text do
    {:error, "No changes made to #{path}. The replacement produced identical content."}
  end

  def call(%{"path" => path, "old_text" => old_text, "new_text" => new_text}, context) do
    sandbox = fetch_sandbox!(context)

    case Sandbox.edit(sandbox, path, old_text, new_text) do
      {:ok, %{occurrences: 0, content: content}} ->
        {:error, find_similar_text(content, old_text, path)}

      {:ok, %{occurrences: count}} when count > 1 ->
        {:error,
         "Found #{count} occurrences of old_text in #{path}. Make the match unique by including more surrounding context."}

      {:ok, %{occurrences: 1}} ->
        diff = generate_diff(old_text, new_text)
        {:ok, Enum.join(["Successfully edited #{path}", diff], "\n\n")}

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, reason} ->
        {:error, "Cannot edit #{path}: #{inspect(reason)}"}
    end
  end

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Edit requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  defp generate_diff(old_text, new_text) do
    old_lines = String.split(old_text, "\n")
    new_lines = String.split(new_text, "\n")

    diff =
      [
        Enum.map(old_lines, &"- #{&1}"),
        Enum.map(new_lines, &"+ #{&1}")
      ]
      |> List.flatten()
      |> Enum.join("\n")

    "```diff\n#{diff}\n```"
  end

  defp find_similar_text(content, old_text, path) do
    old_lines = String.split(old_text, "\n")
    first_line = old_lines |> List.first() |> String.trim()

    cond do
      String.length(first_line) < 5 ->
        "old_text not found in #{path}. Make sure the text matches exactly, including whitespace."

      String.contains?(content, first_line) ->
        """
        old_text not found in #{path}.
        The first line exists in the file, but the full match failed.
        This is often caused by whitespace differences (tabs vs spaces, trailing spaces, or line endings).
        Use the Read tool to see the exact content.
        """
        |> String.trim()

      true ->
        """
        old_text not found in #{path}.
        The text you're looking for doesn't appear in the file.
        Use the Read tool to check the current file contents.
        """
        |> String.trim()
    end
  end
end
