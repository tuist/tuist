defmodule Tuist.Locale do
  @moduledoc false

  @all_languages [
    %{code: "en", label: "English", native: "English"},
    %{code: "es", label: "Spanish", native: "Castellano"},
    %{code: "ja", label: "Japanese", native: "日本語"},
    %{code: "ko", label: "Korean", native: "한국어"},
    %{code: "ru", label: "Russian", native: "Русский"},
    %{code: "yue_Hant", label: "Cantonese", native: "廣東話"},
    %{code: "zh_Hans", label: "Chinese (Simplified)", native: "简体中文"},
    %{code: "zh_Hant", label: "Chinese (Traditional)", native: "繁體中文"}
  ]

  @languages (if Tuist.Environment.dev_single_locale?() do
                Enum.filter(@all_languages, &(&1.code == "en"))
              else
                @all_languages
              end)

  def languages, do: @languages
  def supported_locales, do: Enum.map(@languages, & &1.code)
end
