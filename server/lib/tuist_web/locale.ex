defmodule TuistWeb.Locale do
  @moduledoc """
  Normalizes browser locales into the Gettext locales supported by the app.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView
  alias TuistWeb.Gettext, as: GettextBackend

  @script_by_region %{
    "CN" => "Hans",
    "HK" => "Hant",
    "MO" => "Hant",
    "MY" => "Hans",
    "SG" => "Hans",
    "TW" => "Hant"
  }

  @script_by_language %{
    "yue" => "Hant"
  }

  def on_mount(:assign_locale, _params, session, socket) do
    locale =
      session
      |> Map.get("locale")
      |> normalize_locale()
      |> Kernel.||(connect_locale(socket))

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
    |> case do
      "" -> nil
      locale -> locale_candidates(locale)
    end
    |> case do
      nil ->
        nil

      candidates ->
        supported_locales = Gettext.known_locales(GettextBackend)
        Enum.find(candidates, &(&1 in supported_locales))
    end
  end

  defp connect_locale(socket) do
    case LiveView.get_connect_params(socket) do
      %{"user_locale" => locale} -> locale_from_accept_language(locale)
      _ -> nil
    end
  end

  defp locale_candidates(locale) do
    [language | rest] =
      locale
      |> String.replace("_", "-")
      |> String.split("-", trim: true)

    language = String.downcase(language)

    script =
      rest
      |> Enum.find(&String.match?(&1, ~r/^[A-Za-z]{4}$/))
      |> normalize_script()
      |> Kernel.||(script_for(language, rest))

    case script do
      nil -> [language]
      script -> ["#{language}_#{script}", language]
    end
  end

  defp script_for(language, rest) do
    region =
      Enum.find(rest, &String.match?(&1, ~r/^(?:[A-Za-z]{2}|\d{3})$/))

    @script_by_language[language] || @script_by_region[normalize_region(region)]
  end

  defp normalize_script(nil), do: nil

  defp normalize_script(script) do
    script
    |> String.downcase()
    |> String.capitalize()
  end

  defp normalize_region(nil), do: nil
  defp normalize_region(region), do: String.upcase(region)
end
