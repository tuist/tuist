defmodule Tuist.Marketing.Customers.CaseStudy do
  @moduledoc false
  @enforce_keys [
    :title,
    :date,
    :company,
    :url,
    :founded_date,
    :body,
    :slug,
    :og_image_path,
    :excerpt
  ]
  defstruct [
    :title,
    :date,
    :company,
    :url,
    :founded_date,
    :onboarded_date,
    :body,
    :slug,
    :og_image_path,
    :excerpt,
    translations: %{},
    original_title: nil,
    original_excerpt: nil,
    original_body: nil,
    original_og_image_path: nil
  ]

  def build(filename, attrs, body) do
    title = String.trim_trailing(attrs["title"], ".")
    basename = Path.basename(filename, ".md")
    slug = "/customers/#{basename}"
    og_image_path = attrs["og_image_path"] || default_og_image_path(basename)
    excerpt = attrs["excerpt"]

    struct!(__MODULE__,
      title: title,
      date: Date.from_iso8601!(attrs["date"]),
      company: attrs["company"],
      url: attrs["url"],
      founded_date: attrs["founded_date"],
      onboarded_date: parse_onboarded_date(attrs["onboarded_date"]),
      body: body,
      slug: slug,
      og_image_path: og_image_path,
      excerpt: excerpt,
      translations: normalize_translations(attrs["translations"] || %{}),
      original_title: title,
      original_excerpt: excerpt,
      original_body: body,
      original_og_image_path: og_image_path
    )
  end

  def localize(%__MODULE__{} = case_study, locale) when is_binary(locale) do
    translation = Map.get(case_study.translations, locale, %{})
    original_title = case_study.original_title || case_study.title
    original_excerpt = case_study.original_excerpt || case_study.excerpt
    original_body = case_study.original_body || case_study.body

    %{
      case_study
      | title: Map.get(translation, "title", original_title),
        excerpt: Map.get(translation, "excerpt", original_excerpt),
        body: Map.get(translation, "body", original_body),
        og_image_path: translated_og_image_path(case_study, locale, translation)
    }
  end

  def localize(%__MODULE__{} = case_study, _locale), do: case_study

  defp default_og_image_path(basename) do
    case_study_og_image_path = "/marketing/images/og/customers/#{basename}.jpg"

    if static_asset_exists?(case_study_og_image_path) do
      case_study_og_image_path
    else
      "/marketing/images/og/customers.jpg"
    end
  end

  defp normalize_translations(translations) do
    Enum.into(translations, %{}, fn {locale, translation} ->
      normalized_translation =
        case Map.get(translation, "title") do
          nil -> translation
          title -> Map.put(translation, "title", String.trim_trailing(title, "."))
        end

      {locale, normalized_translation}
    end)
  end

  defp parse_onboarded_date(nil), do: nil
  defp parse_onboarded_date(""), do: nil
  defp parse_onboarded_date(onboarded_date), do: Date.from_iso8601!(onboarded_date)

  defp translated_og_image_path(case_study, locale, translation) do
    base_og_image_path = case_study.original_og_image_path || case_study.og_image_path

    case Map.get(translation, "og_image_path") do
      nil -> maybe_localized_og_image_path(base_og_image_path, locale)
      og_image_path -> og_image_path
    end
  end

  defp maybe_localized_og_image_path(og_image_path, "en"), do: og_image_path

  defp maybe_localized_og_image_path(og_image_path, locale) do
    localized_og_image_path =
      Path.join([Path.dirname(og_image_path), locale, Path.basename(og_image_path)])

    if static_asset_exists?(localized_og_image_path) do
      localized_og_image_path
    else
      og_image_path
    end
  end

  defp static_asset_exists?(path) do
    Application.app_dir(:tuist, "priv/static#{path}")
    |> File.exists?()
  end
end
