defmodule TuistWeb.Marketing.MarketingChangelogEntryLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint TuistWeb.Endpoint

  test "uses the first entry image in social metadata" do
    html =
      build_conn()
      |> get("/changelog/2026.08.21-automation-configuration-history")
      |> html_response(200)

    document = Floki.parse_document!(html)

    assert Floki.attribute(Floki.find(document, ~s(meta[property="og:image"])), "content") == [
             Tuist.Environment.app_url(
               path:
                 TuistWeb.Endpoint.static_path(
                   "/marketing/images/changelog/2026.08.21-automation-configuration-history.png"
                 )
             )
           ]

    assert Floki.find(document, ~s(meta[property="og:image:width"])) == []
    assert Floki.find(document, ~s(meta[property="og:image:height"])) == []
  end
end
