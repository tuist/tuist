defmodule Tuist.Marketing.Blog.CoverArtworkTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Blog.CoverArtwork

  @cover """
  <svg width="352" height="198" viewBox="0 0 352 198" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="352" height="198" fill="#F7F7F7"/>
  <rect width="352" height="198" fill="#FDFDFD"/>
  <rect x="10" y="10" width="100" height="40" rx="4" fill="#E6E8EA" stroke="#c9cccf"/>
  <path d="M0 0h10v10H0z" fill="#191A1B"/>
  <circle cx="20" cy="20" r="4" fill="#6F2CFF"/>
  <circle cx="26" cy="20" r="4" stroke="#8366FF"/>
  <circle cx="30" cy="20" r="4" fill="#FF3B30"/>
  <mask id="m" maskUnits="userSpaceOnUse" fill="black"><rect fill="white" width="10" height="10"/></mask>
  <path mask="url(#m)" d="M0 0h10v10H0z" fill="#A2A5A8"/>
  </svg>
  """

  describe "transform/2" do
    test "the page variant keeps the light paints and tags them with the ramp shade" do
      svg = CoverArtwork.transform(@cover, :page)

      assert svg =~ ~s(<svg data-part="artwork" viewBox="0 0 352 198")
      assert svg =~ ~s(preserveAspectRatio="xMidYMid slice")
      assert svg =~ ~s(fill="#F7F7F7" data-fill="surface-tertiary")
      assert svg =~ ~s(fill="#FDFDFD" data-fill="surface")
      assert svg =~ ~s(fill="#E6E8EA" data-fill="neutral-2")
      assert svg =~ ~s(stroke="#C9CCCF" data-stroke="neutral-4")
      assert svg =~ ~s(fill="#6F2CFF" data-fill="purple")
      assert svg =~ ~s(stroke="#8366FF" data-stroke="purple")
      assert svg =~ ~s(fill="currentColor")
      refute svg =~ "#191A1B"
    end

    test "mask luminance fills are left alone in both variants" do
      for theme <- [:page, :og] do
        svg = CoverArtwork.transform(@cover, theme)

        assert svg =~
                 ~s(<mask id="m" maskUnits="userSpaceOnUse" fill="black"><rect fill="white" width="10" height="10"/></mask>)
      end
    end

    test "the OG variant bakes the dark values in and carries no data attributes" do
      svg = CoverArtwork.transform(@cover, :og)

      assert svg =~ ~s(fill="#181818")
      assert svg =~ ~s(fill="#0E0E0E")
      assert svg =~ ~s(fill="#2E2E2E")
      assert svg =~ ~s(stroke="#464646")
      assert svg =~ ~s(fill="#8366FF")
      assert svg =~ ~s(fill="currentColor")
      refute svg =~ "data-fill"
      refute svg =~ "data-stroke"
    end

    test "brand colors outside the ramp pass through in both variants" do
      assert CoverArtwork.transform(@cover, :page) =~ ~s(fill="#FF3B30")
      assert CoverArtwork.transform(@cover, :og) =~ ~s(fill="#FF3B30")
    end
  end

  describe "available?/1" do
    test "rejects names that are not plain slugs" do
      refute CoverArtwork.available?("../secrets")
      refute CoverArtwork.available?("Not A Slug")
      refute CoverArtwork.available?(nil)
    end

    test "is false for posts without a cover file" do
      refute CoverArtwork.available?("no-such-post")
    end
  end

  test "basename/1 is the last segment of the post's slug" do
    assert CoverArtwork.basename(%{slug: "/blog/2026/07/16/swifterpm"}) == "swifterpm"
  end
end
