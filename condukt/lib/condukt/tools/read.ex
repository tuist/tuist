defmodule Condukt.Tools.Read do
  @moduledoc """
  Tool for reading file contents, after pi's `read` tool.

  Supports text files and images (jpg, png, gif, webp), recognized by their
  content. Images are returned as base64-encoded attachments. Text output is
  cut to 2000 lines or 50KB, whichever comes first, and ends with a notice
  that names the `offset` to continue from.

  All filesystem access goes through the active `Condukt.Sandbox`, so the
  same agent definition behaves identically against the host filesystem
  (`Sandbox.Local`), an in-memory virtual filesystem (`Sandbox.Virtual`), or a
  microVM-backed guest workspace (`Sandbox.Microsandbox`).

  ## Parameters

  - `path` - Path to the file (relative or absolute)
  - `offset` - Line number to start reading from (1-indexed, optional)
  - `limit` - Maximum number of lines to read (optional)
  """

  use Condukt.Tool

  alias Condukt.Sandbox
  alias Condukt.Tools.Truncate

  @impl true
  def name(opts), do: Keyword.get(opts, :name, "Read")

  # Reads change nothing, so an interrupted call can simply run again.
  @impl true
  def replay_safe?, do: true

  @impl true
  def read_only?(_opts), do: true

  @impl true
  def description(_opts) do
    "Read the contents of a file. Supports text files and images (jpg, png, gif, webp). " <>
      "Images are sent as attachments. For text files, output is truncated to #{Truncate.max_lines()} lines " <>
      "or #{div(Truncate.max_bytes(), 1024)}KB (whichever is hit first). Use offset/limit for large files. " <>
      "When you need the full file, continue with offset until complete."
  end

  @impl true
  def parameters(_opts) do
    %{
      type: "object",
      properties: %{
        path: %{
          type: "string",
          description: "Path to the file to read (relative or absolute)"
        },
        offset: %{
          type: "number",
          description: "Line number to start reading from (1-indexed)"
        },
        limit: %{
          type: "number",
          description: "Maximum number of lines to read"
        }
      },
      required: ["path"]
    }
  end

  @impl true
  def call(%{"path" => path} = args, context) do
    sandbox = fetch_sandbox!(context)

    case Sandbox.read(sandbox, path) do
      {:ok, content} ->
        case media_type(content) do
          nil -> format_text(content, path, args["offset"], args["limit"])
          media_type -> {:ok, %{type: :image, media_type: media_type, data: Base.encode64(content)}}
        end

      {:error, :enoent} ->
        {:error, "File not found: #{path}"}

      {:error, :eisdir} ->
        {:error, "#{path} is a directory, not a file"}

      {:error, reason} ->
        {:error, "Cannot read #{path}: #{inspect(reason)}"}
    end
  end

  defp fetch_sandbox!(%{sandbox: %Sandbox{} = sandbox}), do: sandbox

  defp fetch_sandbox!(_) do
    raise ArgumentError,
          "Condukt.Tools.Read requires context.sandbox. " <>
            "When invoking the tool outside a Session, build one with " <>
            "Condukt.Sandbox.new(Condukt.Sandbox.Local, cwd: \"...\")."
  end

  # Images are recognized by their signature, not their extension.
  defp media_type(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: "image/png"
  defp media_type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  defp media_type(<<"GIF8", v, "a", _::binary>>) when v in [?7, ?9], do: "image/gif"
  defp media_type(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp media_type(_content), do: nil

  # Lines are numbered as `String.split(content, "\\n")` splits them, so a
  # final newline ends with an empty last line, as in pi.
  defp format_text(content, path, offset, limit) do
    lines = String.split(content, "\n")
    total = length(lines)
    offset = if is_number(offset), do: trunc(offset)
    limit = if is_number(limit), do: max(trunc(limit), 0)
    start = if offset && offset > 0, do: offset - 1, else: 0

    if start >= total and offset do
      {:error, "Offset #{offset} is beyond end of file (#{total} lines total)"}
    else
      selected = if limit, do: Enum.slice(lines, start, limit), else: Enum.drop(lines, start)
      truncation = Truncate.head(Enum.join(selected, "\n"))
      remaining = if limit, do: total - start - length(selected), else: 0
      {:ok, describe(truncation, path, lines, start, total, remaining)}
    end
  end

  defp describe(%{first_line_exceeds_limit: true}, path, lines, start, _total, _remaining) do
    size = lines |> Enum.at(start) |> byte_size() |> Truncate.format_size()
    max = Truncate.format_size(Truncate.max_bytes())

    "[Line #{start + 1} is #{size}, exceeds #{max} limit. " <>
      "Use bash: sed -n '#{start + 1}p' #{path} | head -c #{Truncate.max_bytes()}]"
  end

  defp describe(%{truncated: true} = truncation, _path, _lines, start, total, _remaining) do
    last = start + truncation.output_lines
    by = if truncation.truncated_by == :bytes, do: " (#{Truncate.format_size(Truncate.max_bytes())} limit)", else: ""

    truncation.content <>
      "\n\n[Showing lines #{start + 1}-#{last} of #{total}#{by}. Use offset=#{last + 1} to continue.]"
  end

  defp describe(truncation, _path, _lines, start, _total, remaining) when remaining > 0 do
    next = start + truncation.output_lines + 1
    truncation.content <> "\n\n[#{remaining} more lines in file. Use offset=#{next} to continue.]"
  end

  defp describe(truncation, _path, _lines, _start, _total, _remaining), do: truncation.content
end
