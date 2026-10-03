defmodule TuistWeb.Marketing.SocialCardsTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Marketing.SocialCards

  describe "head_image/2" do
    test "uses the designed card when the page has one" do
      assert SocialCards.head_image("compute", fn -> flunk("fallback signed") end) ==
               Tuist.Environment.app_url(path: "/marketing/images/og/compute.png", marketing: true)
    end

    test "falls back when the page has no designed card" do
      assert SocialCards.head_image("support", fn -> "/open-graph-images/abc.jpg" end) ==
               Tuist.Environment.app_url(path: "/open-graph-images/abc.jpg", marketing: true)
    end
  end

  test "every designed card ships as a static image" do
    for card <-
          ~w(home about brand download pricing blog cache tests compute previews customers changelog newsletter community docs imprint privacy openness security cookies terms longevity data-act-addendum data-processing-addendum service-level-addendum trademark-guidelines) do
      assert SocialCards.available?(card)
      assert File.regular?(Application.app_dir(:tuist, "priv/static/marketing/images/og/#{card}.png")), card
    end

    refute SocialCards.available?("support")
    assert_raise ArgumentError, fn -> SocialCards.image_url("support") end
  end
end
