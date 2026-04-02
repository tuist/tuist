defmodule TuistWeb.Locale do
  @moduledoc """
  Normalizes browser locales into the Gettext locales supported by the app.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView
  alias TuistWeb.Gettext, as: GettextBackend

  @supported_locales ~w(en es ja ko ru yue_Hant zh_Hans zh_Hant)

  def supported_locales, do: @supported_locales

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
        [language, script | _] when String.match?(script, ~r/^[A-Za-z]{4}$/) ->
          "#{String.downcase(language)}_#{normalize_script(script)}"

        [language | _] ->
          String.downcase(language)
      end

    if candidate in supported_locales(), do: candidate
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
      String.starts_with?(locale, "zh-hans") -> "zh_Hans"
      String.starts_with?(locale, "zh-hant") -> "zh_Hant"
      String.starts_with?(locale, "zh-cn") -> "zh_Hans"
      String.starts_with?(locale, "zh-my") -> "zh_Hans"
      String.starts_with?(locale, "zh-sg") -> "zh_Hans"
      String.starts_with?(locale, "zh-hk") -> "zh_Hant"
      String.starts_with?(locale, "zh-mo") -> "zh_Hant"
      String.starts_with?(locale, "zh-tw") -> "zh_Hant"
      true -> nil
    end
  end
end
