defmodule TuistWeb.Plugs.AttributionPlug do
  @moduledoc """
  Reads where a visit came from for `Tuist.Marketing.Attribution`, from the
  URL and the `Referer` header only. It sets no cookie, writes nothing to the
  session and reads nothing from the visitor's device, so it needs no consent
  banner.

    * `:landing` (marketing and documentation pages): a request whose URL
      carries campaign parameters is answered `private, no-store`, so shared
      caches pass every one of them through to be counted. When it arrived
      from another site or without a `Referer`, and is not redirected, it is
      counted as a landing. Following a link within the site keeps the
      parameters (the marketing script carries them along) but has a
      same-site `Referer`, so it is not counted again.
    * `:signup` (the sign-up and sign-in pages): a visit from another site
      without campaign parameters is redirected to the same page with the site
      as `utm_source` and `referral` as `utm_medium`, so the page's URL carries
      the first touch like any campaign link.
    * `:oauth_request` (an identity provider sign-in starting): the campaign
      the sign-up page passed along is held on the server for an hour under
      the OAuth `state` sent through the provider, for the callback to pick up.
  """
  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn

  alias Tuist.Marketing.Attribution

  @signup_entry_paths ["/users/register", "/users/log_in"]

  # Previews, crawlers and agents fetching on someone's behalf are not visits.
  @non_human_user_agent ~r/bot|crawl|spider|slurp|preview|headless|fetch|ChatGPT-User|python|curl|wget/i

  def init(action) when action in [:landing, :signup, :oauth_request], do: action

  def call(%Plug.Conn{method: "GET"} = conn, :landing) do
    conn = fetch_query_params(conn)

    case Attribution.from_params(conn.query_params) do
      nil ->
        conn

      attribution ->
        # Counted on the way out, so a visit that a locale or legacy redirect
        # sends on to another page is counted once, on the page it ends on.
        # Controllers set their own cache-control later, so it is overridden
        # here too.
        register_before_send(conn, fn conn ->
          if conn.status not in 300..399 and not internal_navigation?(conn) and human?(conn) do
            Attribution.record_landing(attribution, conn.request_path, referrer_host(conn))
          end

          put_resp_header(conn, "cache-control", "private, no-store")
        end)
    end
  end

  # Only where sign-ups start: the other pages in the flow are reached through
  # redirects that keep the identity provider's page as the `Referer`.
  def call(%Plug.Conn{method: "GET", request_path: path} = conn, :signup) when path in @signup_entry_paths do
    conn = fetch_query_params(conn)

    with nil <- Attribution.from_params(conn.query_params),
         host when is_binary(host) <- referrer_host(conn) do
      # Appended to the raw query, which keeps the page's own parameters
      # exactly as they came, nested and repeated ones included.
      query =
        [conn.query_string, URI.encode_query(%{"utm_source" => host, "utm_medium" => "referral"})]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("&")

      conn
      |> redirect(to: path <> "?" <> query)
      |> halt()
    else
      _ -> conn
    end
  end

  def call(%Plug.Conn{method: "GET"} = conn, :oauth_request) do
    conn = fetch_query_params(conn)

    case Attribution.from_params(conn.query_params) do
      nil ->
        conn

      attribution ->
        # Keyed by the `state` of the provider redirect, exactly as the
        # provider sends it back to the callback.
        register_before_send(conn, fn conn ->
          with [location] <- get_resp_header(conn, "location"),
               %URI{query: query} when is_binary(query) <- URI.parse(location),
               %{"state" => state} <- URI.decode_query(query) do
            Attribution.hold(["oauth_state", state], attribution)
          end

          conn
        end)
    end
  end

  def call(conn, _action), do: conn

  defp referrer_host(conn) do
    conn |> get_req_header("referer") |> List.first() |> Attribution.external_referrer_host(conn.host)
  end

  # A `Referer` from this site: a link followed within it, which carries the
  # campaign along but is not a new arrival. A missing `Referer` counts, as
  # apps and privacy settings often send none.
  defp internal_navigation?(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> same_host?(URI.parse(referer).host, conn.host)
      [] -> false
    end
  end

  defp same_host?(host, own_host) when is_binary(host) and is_binary(own_host) do
    String.replace_prefix(String.downcase(host), "www.", "") ==
      String.replace_prefix(String.downcase(own_host), "www.", "")
  end

  defp same_host?(_host, _own_host), do: false

  defp human?(conn) do
    case get_req_header(conn, "user-agent") do
      [user_agent | _] -> not Regex.match?(@non_human_user_agent, user_agent)
      [] -> false
    end
  end
end
