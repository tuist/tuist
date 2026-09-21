defmodule AtlasWeb.Plugs.PagesSubdomain do
  @moduledoc """
  Route requests to `<slug>.<host_suffix>` into `AtlasWeb.PagesServeController`
  instead of the main router. Everything else (the apex `atlas.tuist.dev`,
  localhost, IP hits, `www.…` unless someone maps it) falls through to the
  normal Phoenix router.

  Configure the wildcard root via
  `config :atlas, AtlasWeb.Plugs.PagesSubdomain, host_suffix: "atlas.tuist.dev"`.
  When unset the plug is inert, so dev and test remain single-host.
  """

  import Plug.Conn

  alias AtlasWeb.PagesServeController
  alias AtlasWeb.Plugs.RequireAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    with suffix when is_binary(suffix) <- host_suffix(),
         host when is_binary(host) <- conn.host,
         {:ok, slug} <- extract_slug(host, suffix) do
      conn
      |> assign(:pages_slug, slug)
      |> fetch_session([])
      |> fetch_query_params()
      |> put_private(:phoenix_endpoint, AtlasWeb.Endpoint)
      |> RequireAuth.call([])
      |> maybe_serve(slug)
    else
      _no_match -> conn
    end
  end

  defp maybe_serve(%Plug.Conn{halted: true} = conn, _slug), do: conn

  defp maybe_serve(conn, slug) do
    conn
    |> PagesServeController.call(PagesServeController.init(action: :serve, slug: slug))
    |> halt()
  end

  defp host_suffix do
    Application.get_env(:atlas, __MODULE__, [])
    |> Keyword.get(:host_suffix)
  end

  defp extract_slug(host, suffix) do
    suffix = String.trim_leading(suffix, ".")

    cond do
      host == suffix ->
        :error

      String.ends_with?(host, "." <> suffix) ->
        prefix = String.slice(host, 0, byte_size(host) - byte_size(suffix) - 1)

        if valid_single_label?(prefix) do
          {:ok, String.downcase(prefix)}
        else
          :error
        end

      true ->
        :error
    end
  end

  defp valid_single_label?(label) do
    is_binary(label) and
      label != "" and
      not String.contains?(label, ".") and
      Regex.match?(~r/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i, label)
  end
end
