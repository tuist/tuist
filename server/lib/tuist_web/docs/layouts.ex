defmodule TuistWeb.Docs.Layouts do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.AppLayoutComponents, only: [headerbar_breadcrumbs: 1]

  alias Tuist.Docs.Paths

  embed_templates "layouts/*"

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)

  defp language_name(locale) do
    case Enum.find(TuistWeb.Marketing.Localization.languages(), &(&1.code == locale)) do
      %{label: label} -> label
      _ -> "English"
    end
  end

  defp localized_docs_href(current_path, target_locale) do
    case current_path |> Path.split() |> Enum.reject(&(&1 == "/")) do
      [_locale, "docs" | rest] -> Path.join(["/#{target_locale}", "docs" | rest])
      _ -> "/#{target_locale}/docs"
    end
  end
end
