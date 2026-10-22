defmodule AtlasWeb.NativeLinks do
  @moduledoc """
  The single allowlist of web paths that correspond to native Atlas destinations.

  It drives Apple's app-site association, the public `/open` landing page, and the
  dashboard's explicit "Open in Atlas" action. Destinations are navigation intents
  only: the server never reads a record to build them, and the native clients still
  authorize every record they load. Screen keys must match the native destination
  catalog (`atlas-native/core/src/destinations.rs`) and are frozen once shipped.

  Matching is exact. Only the listed pages and one lowercase UUID segment are
  recognized; children such as `/new`, `/edit`, settings sub-pages, and actions are
  never claimed. `/commercial/finance` maps to native invoices for the explicit
  header action only. The web finance dashboard is not equivalent to native invoice
  bookkeeping, so universal and app links never claim it.
  """

  alias AtlasWeb.NativeLinks.Config

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @uuid_pattern "????????-????-????-????-????????????"

  # page: the web page equivalent to the native screen.
  # claimed?: whether universal/app links may open the page natively.
  # record_page: the web detail page for a record, if one exists.
  @destinations [
    %{screen: "tasks", page: "/tasks", claimed?: true, record_page: nil},
    %{
      screen: "accounts",
      page: "/commercial/sales/accounts",
      claimed?: true,
      record_page: "/commercial/sales/accounts"
    },
    %{screen: "invoices", page: "/commercial/finance", claimed?: false, record_page: nil},
    %{screen: "time-off", page: "/people/time-off", claimed?: true, record_page: nil},
    %{screen: "people", page: "/people", claimed?: true, record_page: nil},
    %{screen: "profile", page: "/settings", claimed?: true, record_page: nil}
  ]
  @record_screens ~w(tasks accounts invoices)

  def screens, do: Enum.map(@destinations, & &1.screen)

  @doc "The native destination for an existing dashboard page, ignoring any query string."
  def for_page(path) when is_binary(path) do
    Enum.find_value(@destinations, &page_destination(&1, path))
  end

  def for_page(_path), do: nil

  defp page_destination(%{page: path, screen: screen}, path), do: {screen, nil}

  defp page_destination(%{record_page: record_page, screen: screen}, path) when is_binary(record_page) do
    case String.split(path, record_page <> "/", parts: 2) do
      ["", id] -> if uuid?(id), do: {screen, id}
      _ -> nil
    end
  end

  defp page_destination(_destination, _path), do: nil

  @doc "The native destination for `/open/<screen>[/<uuid>]` path segments."
  def for_open([screen]) when is_binary(screen) do
    if screen in screens(), do: {screen, nil}
  end

  def for_open([screen, id]) when is_binary(screen) and is_binary(id) do
    if screen in @record_screens and uuid?(id), do: {screen, id}
  end

  def for_open(_segments), do: nil

  @doc """
  The custom-scheme navigation link for a destination, bound to the configured
  HTTPS origin. Returns nil without one; the request's Host header is never used.
  """
  def native_url({screen, id}) do
    case Config.origin() do
      nil ->
        nil

      origin ->
        path = Enum.join(["navigate", screen | List.wrap(id)], "/")
        "dev.tuist.atlas://#{path}?server=#{URI.encode(origin, &URI.char_unreserved?/1)}"
    end
  end

  @doc "The sign-in protected web page to continue with in a browser."
  def browser_path({screen, id}) do
    destination = Enum.find(@destinations, &(&1.screen == screen))

    case {destination.record_page, id} do
      {record_page, id} when is_binary(record_page) and is_binary(id) -> "#{record_page}/#{id}"
      _ -> destination.page
    end
  end

  @doc "Apple app-site association path components, in claim order."
  def claimed_paths do
    pages =
      Enum.flat_map(@destinations, fn destination ->
        if destination.claimed? do
          [destination.page | List.wrap(destination.record_page && "#{destination.record_page}/#{@uuid_pattern}")]
        else
          []
        end
      end)

    open = Enum.map(screens(), &"/open/#{&1}") ++ Enum.map(@record_screens, &"/open/#{&1}/#{@uuid_pattern}")
    pages ++ open
  end

  defp uuid?(value), do: Regex.match?(@uuid, value)
end
