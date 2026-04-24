defmodule TuistWeb.DocsMarkdown do
  @moduledoc false

  alias Tuist.Docs
  alias Tuist.Docs.Paths
  alias TuistWeb.Marketing.Localization

  def from_request_path(request_path) when is_binary(request_path) do
    with {:ok, locale, path_segments} <- request_path_info(request_path) do
      get(locale, path_segments)
    end
  end

  def get(locale, path_segments) when is_binary(locale) and is_list(path_segments) do
    locale
    |> Paths.slug(path_segments)
    |> Docs.get_page()
    |> case do
      %{markdown: markdown} when is_binary(markdown) and markdown != "" -> {:ok, markdown}
      _ -> :error
    end
  end

  defp request_path_info(request_path) do
    case String.split(request_path, "/", trim: true) do
      [locale, "docs" | path_segments] ->
        if locale in Localization.all_locales() do
          {:ok, locale, path_segments}
        else
          :error
        end

      _ ->
        :error
    end
  end
end
