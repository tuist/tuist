defmodule TuistWeb.Locale do
  @moduledoc """
  Normalizes browser locales into the Gettext locales supported by the app.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView
  alias Tuist.Locale, as: SharedLocale
  alias TuistWeb.Gettext, as: GettextBackend

  def supported_locales, do: SharedLocale.supported_locales()

  def on_mount(:assign_locale, _params, session, socket) do
    locale =
      session
      |> Map.get("locale")
      |> normalize_locale()

    locale = locale || connect_locale(socket)

    if locale do
      Gettext.put_locale(GettextBackend, locale)
    end

    {:cont, assign(socket, :locale, locale || Gettext.get_locale(GettextBackend))}
  end

  def locale_from_accept_language(nil), do: nil

  def locale_from_accept_language(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(fn locale ->
      locale
      |> String.split(";")
      |> List.first()
      |> String.trim()
    end)
    |> Enum.find_value(&normalize_locale/1)
  end

  def normalize_locale(nil), do: nil

  def normalize_locale(locale) when is_binary(locale) do
    locale
    |> String.trim()
    |> String.replace("_", "-")
    |> case do
      "" -> nil
      locale -> exact_supported_locale(locale) || chinese_locale(locale)
    end
  end

  defp connect_locale(socket) do
    case LiveView.get_connect_params(socket) do
      %{"user_locale" => locale} -> locale_from_accept_language(locale)
      _ -> nil
    end
  end

  defp exact_supported_locale(locale) do
    candidate =
      case String.split(locale, "-", trim: true) do
        [] ->
          nil

        [language, script | _] ->
          if script_locale?(script) do
            "#{String.downcase(language)}_#{normalize_script(script)}"
          else
            String.downcase(language)
          end

        [language | _] ->
          String.downcase(language)
      end

    if candidate in supported_locales(), do: candidate
  end

  defp script_locale?(script) do
    String.length(script) == 4 and String.match?(script, ~r/^[A-Za-z]+$/)
  end

  defp normalize_script(nil), do: nil

  defp normalize_script(script) do
    script
    |> String.downcase()
    |> String.capitalize()
  end

  # Browsers often send region-based Chinese tags while Gettext uses script-based locales.
  defp chinese_locale(locale) do
    locale = String.downcase(locale)

    cond do
      locale == "yue" or String.starts_with?(locale, "yue-") -> "yue_Hant"
      zh_hans_locale?(locale) -> "zh_Hans"
      zh_hant_locale?(locale) -> "zh_Hant"
      true -> nil
    end
  end

  defp zh_hans_locale?(locale) do
    String.starts_with?(locale, "zh-hans") or
      String.starts_with?(locale, "zh-cn") or
      String.starts_with?(locale, "zh-my") or
      String.starts_with?(locale, "zh-sg")
  end

  defp zh_hant_locale?(locale) do
    String.starts_with?(locale, "zh-hant") or
      String.starts_with?(locale, "zh-hk") or
      String.starts_with?(locale, "zh-mo") or
      String.starts_with?(locale, "zh-tw")
  end
end
