defmodule TuistWeb.Marketing.Localization do
  @moduledoc ~S"""
  This module contains utilities to handle localization in the marketing pages:

  - Plugs and LiveView on_mount callbacks to set the local to the process using `Gettext.put_locale/1`
  - Logic to extract the locale from the `Accept-Language` header.
  - Logic to redirect to the localized route based on the locale extracted from the `Accept-Language` header.
  """
  @behaviour Plug

  import Plug.Conn

  @additional_locales ["ko", "ja"]

  def init(:put_locale), do: :put_locale
  def init(:redirect_to_localized_route), do: :redirect_to_localized_route

  def all_locales, do: @additional_locales ++ ["en"]
  def additional_locales, do: @additional_locales

  def call(conn, :put_locale) do
    locale = Map.get(conn.private, :locale)

    if is_nil(locale) do
      conn
    else
      Gettext.put_locale(locale)

      put_session(conn, :locale, locale)
    end
  end

  def call(conn, :redirect_to_localized_route) do
    private_locale = Map.get(conn.private, :locale, "en")
    headers_locale = fetch_locale_from_headers(conn) || "en"

    disable_locale_redirect =
      Map.get(conn.query_params, "disable_locale_redirect", "false") == "true"

    if Enum.member?(all_locales(), headers_locale) and private_locale != headers_locale and
         !disable_locale_redirect do
      redirect_to_path =
        Path.join(
          locale_path_prefix(headers_locale),
          if(conn.query_string == "",
            do: path_without_locale(conn.request_path),
            else: "#{path_without_locale(conn.request_path)}?#{conn.query_string}"
          )
        )

      conn
      |> put_status(:moved_permanently)
      |> Phoenix.Controller.redirect(
        to: redirect_to_path,
        status: 301
      )
      |> halt()
    else
      conn
    end
  end

  def path_without_locale(path) do
    Enum.reduce(all_locales(), path, fn locale, acc ->
      prefix = "^" <> Regex.escape(locale_path_prefix(locale)) <> "/"
      Regex.replace(~r/#{prefix}/, acc, "/")
    end)
  end

  def locale_path_prefix("en") do
    "/"
  end

  def locale_path_prefix(locale) do
    "/#{locale}"
  end

  def on_mount(:default, _params, %{"locale" => locale} = _session, socket) do
    Gettext.put_locale(locale)
    {:cont, socket}
  end

  defp fetch_locale_from_headers(conn) do
    conn
    |> locales_from_accept_language()
    |> Enum.map(fn locale -> validate_locale(locale) end)
    |> Enum.find(&(not is_nil(&1)))
  end

  # Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7
  defp locales_from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [value | _] ->
        values = String.split(value, ",")
        Enum.map(values, &resolve_locale_from_accept_language/1)

      _ ->
        []
    end
  end

  defp resolve_locale_from_accept_language(language) do
    language
    |> String.split(";")
    |> List.first()
    |> language_to_locale()
  end

  defp language_to_locale(language) do
    String.replace(language, "-", "_", global: false)
  end

  defp validate_locale(nil), do: nil

  defp validate_locale(locale) do
    supported_locales = Gettext.known_locales(TuistWeb.Gettext)

    case String.split(locale, "_") do
      [language, _] ->
        Enum.find([language, locale], fn locale ->
          locale in supported_locales
        end)

      [^locale] ->
        if locale in supported_locales do
          locale
        end
    end
  end
end
