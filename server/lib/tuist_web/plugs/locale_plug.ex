defmodule TuistWeb.Plugs.LocalePlug do
  @moduledoc """
  Plug that keeps the current request locale aligned with the browser language.
  """

  import Plug.Conn

  alias TuistWeb.Gettext, as: GettextBackend
  alias TuistWeb.Locale

  def init(opts), do: opts

  def call(conn, _opts) do
    locale =
      conn
      |> get_req_header("accept-language")
      |> List.first()
      |> Locale.locale_from_accept_language()
      |> Kernel.||(conn |> get_session(:locale) |> Locale.normalize_locale())

    if locale do
      Gettext.put_locale(GettextBackend, locale)
      put_session(conn, :locale, locale)
    else
      conn
    end
  end
end
