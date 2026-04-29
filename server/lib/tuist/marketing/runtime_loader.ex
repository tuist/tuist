defmodule Tuist.Marketing.RuntimeLoader do
  @moduledoc false

  def build!(opts) do
    builder = Keyword.fetch!(opts, :build)
    from = Keyword.fetch!(opts, :from)
    parser_module = Keyword.get(opts, :parser)

    for highlighter <- Keyword.get(opts, :highlighters, []) do
      Application.ensure_all_started(highlighter)
    end

    from
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      parsed_contents = parse_contents!(path, File.read!(path), parser_module)
      build_entry(builder, path, parsed_contents, opts)
    end)
  end

  defp build_entry(builder, path, {_attrs, _body} = parsed_contents, opts) do
    build_entry(builder, path, [parsed_contents], opts)
  end

  defp build_entry(builder, path, parsed_contents, opts) when is_list(parsed_contents) do
    converter_module = Keyword.get(opts, :html_converter)

    Enum.map(parsed_contents, fn {attrs, body} ->
      body =
        case converter_module do
          nil -> path |> Path.extname() |> String.downcase() |> convert_body(body, opts)
          module -> module.convert(path, body, attrs, opts)
        end

      builder.build(path, attrs, body)
    end)
  end

  defp parse_contents!(path, contents, nil) do
    case parse_contents(path, contents) do
      {:ok, attrs, body} ->
        {attrs, body}

      {:error, message} ->
        raise """
        #{message}

        Each entry must have a map with attributes, followed by --- and a body.
        """
    end
  end

  defp parse_contents!(path, contents, parser_module) do
    parser_module.parse(path, contents)
  end

  defp parse_contents(path, contents) do
    case :binary.split(contents, ["\n---\n", "\r\n---\r\n"]) do
      [_] ->
        {:error, "could not find separator --- in #{inspect(path)}"}

      [code, body] ->
        case Code.eval_string(code, []) do
          {%{} = attrs, _} ->
            {:ok, attrs, body}

          {other, _} ->
            {:error, "expected attributes for #{inspect(path)} to return a map, got: #{inspect(other)}"}
        end
    end
  end

  defp convert_body(extname, body, opts) when extname in [".md", ".markdown", ".livemd"] do
    earmark_opts = Keyword.get(opts, :earmark_options, %Earmark.Options{})
    html = Earmark.as_html!(body, earmark_opts)

    case Keyword.get(opts, :highlighters, []) do
      [] -> html
      [_ | _] -> NimblePublisher.highlight(html)
    end
  end

  defp convert_body(_extname, body, _opts) do
    body
  end
end
