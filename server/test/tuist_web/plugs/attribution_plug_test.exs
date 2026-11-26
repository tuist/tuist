defmodule TuistWeb.Plugs.AttributionPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Marketing.Attribution.Landing

  @browser "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 Safari/605.1.15"

  defp visit(conn, path, referer, user_agent \\ @browser) do
    conn
    |> put_req_header("user-agent", user_agent)
    |> then(&if(referer, do: put_req_header(&1, "referer", referer), else: &1))
    |> get(path)
  end

  defp landings(campaign) do
    Landing.Buffer.flush()
    ClickHouseRepo.all(from(l in Landing, where: l.campaign == ^campaign))
  end

  test "counts a campaign landing from another site and keeps it out of shared caches", %{conn: conn} do
    conn = visit(conn, "/about?utm_source=ChatGPT.com&utm_medium=AI&utm_campaign=landing-test", "https://chatgpt.com/c/1")

    assert html_response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]

    assert [%{source: "chatgpt.com", medium: "ai", referrer_host: "chatgpt.com", path: "/about"}] =
             landings("landing-test")
  end

  test "does not count a campaign page reached from within the site", %{conn: conn} do
    conn = visit(conn, "/pricing?utm_source=chatgpt.com&utm_campaign=internal-test", "http://www.example.com/about")

    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert landings("internal-test") == []
  end

  test "counts a visit that arrives without a Referer", %{conn: conn} do
    visit(conn, "/about?utm_source=chatgpt.com&utm_campaign=no-referer-test", nil)

    assert [%{source: "chatgpt.com", referrer_host: "", path: "/about"}] = landings("no-referer-test")
  end

  test "counts a visit once on the page a redirect sends it to", %{conn: conn} do
    conn = visit(conn, "/case-studies?utm_source=chatgpt.com&utm_campaign=redirect-test", "https://chatgpt.com/")
    assert redirected_to(conn, 301) =~ "/customers?"

    conn
    |> redirected_to(301)
    |> then(&visit(build_conn(), &1, "https://chatgpt.com/"))
    |> html_response(200)

    assert [%{path: "/customers"}] = landings("redirect-test")
  end

  test "does not count crawlers", %{conn: conn} do
    visit(conn, "/about?utm_source=chatgpt.com&utm_campaign=crawler-test", "https://chatgpt.com/", "GPTBot/1.1")

    assert landings("crawler-test") == []
  end

  test "leaves pages without a campaign cacheable", %{conn: conn} do
    conn = visit(conn, "/about", "https://chatgpt.com/")

    assert get_resp_header(conn, "cache-control") == ["public, max-age=60, stale-while-revalidate=86400"]
  end

  test "puts the referring site of a sign-up page visit into its URL instead of the session", %{conn: conn} do
    conn = visit(conn, "/users/register?return_to=/x", "https://news.ycombinator.com/item?id=1")

    assert redirected_to(conn) =~ "/users/register?"

    assert %{"utm_source" => "news.ycombinator.com", "utm_medium" => "referral", "return_to" => "/x"} =
             conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert conn |> get_resp_header("set-cookie") |> Enum.join() |> String.contains?("utm") == false
  end

  test "keeps the sign-up page's own query exactly when adding the referring site", %{conn: conn} do
    conn = visit(conn, "/users/register?a[b]=1&x=1&x=2", "https://news.ycombinator.com/")

    assert redirected_to(conn) ==
             "/users/register?a[b]=1&x=1&x=2&utm_medium=referral&utm_source=news.ycombinator.com"
  end

  test "leaves sign-up pages with a campaign, or reached from within the site, alone", %{conn: conn} do
    assert conn |> visit("/users/register?utm_source=newsletter", "https://news.ycombinator.com/") |> html_response(200)
    assert build_conn() |> visit("/users/register", "http://www.example.com/pricing") |> html_response(200)
  end
end
