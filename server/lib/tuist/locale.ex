defmodule Tuist.Locale do
  @moduledoc false

  @all_languages [
    %{code: "en", label: "English", native: "English"},
    %{code: "es", label: "Spanish", native: "Castellano"},
    %{code: "ja", label: "Japanese", native: "日本語"},
    %{code: "ka", label: "Georgian", native: "ქართული"},
    %{code: "ko", label: "Korean", native: "한국어"},
    %{code: "ru", label: "Russian", native: "Русский"},
    %{code: "yue_Hant", label: "Cantonese", native: "廣東話"},
    %{code: "zh_Hans", label: "Chinese (Simplified)", native: "简体中文"},
    %{code: "zh_Hant", label: "Chinese (Traditional)", native: "繁體中文"}
  ]

  @languages (if Tuist.Environment.single_locale?() do
                Enum.filter(@all_languages, &(&1.code == "en"))
              else
                @all_languages
              end)

  @additional_locales @languages |> Enum.map(& &1.code) |> Enum.reject(&(&1 == "en"))

  def languages, do: @languages
  def supported_locales, do: Enum.map(@languages, & &1.code)

  @doc """
  Rewrites the locale segment of a router path to `:locale`.

  The marketing and docs routes are generated once per locale, so every metric
  labelled by route path carries one series per locale per page. Folding the
  localized variants into a single label keeps that cardinality flat as locales
  are added. English is left alone: its marketing routes carry no prefix, and
  its traffic is worth reading on its own.
  """
  def collapse_locale_path_prefix(path) when is_binary(path) do
    case String.split(path, "/", parts: 3) do
      ["", locale] -> if locale in @additional_locales, do: "/:locale", else: path
      ["", locale, rest] -> if locale in @additional_locales, do: "/:locale/" <> rest, else: path
      _ -> path
    end
  end
end
