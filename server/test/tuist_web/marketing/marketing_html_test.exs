defmodule TuistWeb.Marketing.MarketingHTMLTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Marketing.MarketingHTML

  test "content_html optimizes same-origin images" do
    html = ~s(<p><img src="/marketing/images/example.png" alt="Example"></p>)

    [image] =
      html
      |> MarketingHTML.content_html()
      |> Floki.parse_fragment!()
      |> Floki.find("img")

    assert Floki.attribute(image, "src") == [
             TuistWeb.Endpoint.static_path("/marketing/images/example.png")
           ]

    assert Floki.attribute(image, "loading") == ["lazy"]
    assert Floki.attribute(image, "decoding") == ["async"]
  end

  test "content_html keeps external image sources and explicit loading strategy" do
    html = ~s(<img src="https://example.com/image.png" loading="eager">)

    [image] =
      html
      |> MarketingHTML.content_html()
      |> Floki.parse_fragment!()
      |> Floki.find("img")

    assert Floki.attribute(image, "src") == ["https://example.com/image.png"]
    assert Floki.attribute(image, "loading") == ["eager"]
    assert Floki.attribute(image, "decoding") == ["async"]
  end
end
