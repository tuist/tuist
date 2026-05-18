defmodule Tuist.Docs.Paths do
  @moduledoc false

  def root_path(locale) when is_binary(locale), do: "/#{locale}/docs"

  def public_path(locale, path_segments) when is_list(path_segments) do
    case path_segments do
      [] -> root_path(locale)
      _ -> Path.join(root_path(locale), Enum.join(path_segments, "/"))
    end
  end

  def public_path(locale, "/" <> _ = relative_path) when is_binary(locale) do
    public_path(locale, String.split(relative_path, "/", trim: true))
  end

  def public_path_from_slug("/" <> _ = slug) do
    case String.split(slug, "/", trim: true) do
      [locale | path_segments] -> public_path(locale, path_segments)
      [] -> root_path("en")
    end
  end

  def slug(locale, path_segments \\ []) when is_list(path_segments) do
    case path_segments do
      [] -> "/#{locale}"
      _ -> "/" <> Enum.join([locale | path_segments], "/")
    end
  end
end
