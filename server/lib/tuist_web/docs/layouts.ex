defmodule TuistWeb.Docs.Layouts do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  import TuistWeb.AccountDropdown

  alias Tuist.Docs.Paths

  embed_templates "layouts/*"

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)

  defp open_mobile_nav do
    {"data-open", ""}
    |> JS.set_attribute(to: "#docs-mobile-nav")
    |> JS.set_attribute({"data-mobile-nav-open", ""}, to: "body")
    |> JS.set_attribute({"aria-expanded", "true"}, to: "#docs-nav-mobile-menu")
    |> JS.focus_first(to: "#docs-mobile-nav")
  end

  defp close_mobile_nav do
    "data-open"
    |> JS.remove_attribute(to: "#docs-mobile-nav")
    |> JS.remove_attribute("data-mobile-nav-open", to: "body")
    |> JS.set_attribute({"aria-expanded", "false"}, to: "#docs-nav-mobile-menu")
    |> JS.focus(to: "#docs-nav-mobile-menu")
  end

  defp mobile_nav_sections(locale) do
    [
      %{label: dgettext("docs", "Guides"), href: docs_path("/#{locale}")},
      %{label: dgettext("docs", "CLI"), href: docs_path("/#{locale}/cli")},
      %{
        label: dgettext("docs", "References"),
        href: docs_path("/#{locale}/references/tuist-toml")
      },
      %{label: dgettext("docs", "Resources"), href: docs_path("/#{locale}/contributors/code")}
    ]
  end

  defp mobile_nav_socials do
    [
      %{
        label: dgettext("docs", "GitHub"),
        icon: "brand_github",
        href: "https://github.com/tuist/tuist"
      },
      %{
        label: dgettext("docs", "Mastodon"),
        icon: "brand_mastodon",
        href: "https://fosstodon.org/@tuist"
      },
      %{label: dgettext("docs", "Slack"), icon: "brand_slack", href: "https://slack.tuist.dev"},
      %{
        label: dgettext("docs", "Bluesky"),
        icon: "brand_bluesky",
        href: "https://bsky.app/profile/tuist.dev"
      },
      %{label: "X", icon: "brand_x", href: "https://x.com/tuistdev"}
    ]
  end

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
