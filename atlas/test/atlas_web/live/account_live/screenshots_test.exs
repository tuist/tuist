defmodule AtlasWeb.AccountLive.ScreenshotsTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.AccountLive.Screenshots

  describe "stage/2" do
    test "accepts valid screenshots and preserves order" do
      first = Base.encode64("first")
      second = Base.encode64("second")

      assert {[first_screenshot, second_screenshot], nil} =
               Screenshots.stage([], [
                 %{"data" => first, "media_type" => "image/png", "size" => byte_size(first)},
                 %{"data" => second, "media_type" => "image/webp", "size" => byte_size(second)}
               ])

      assert first_screenshot.id == Screenshots.id(first)
      assert second_screenshot.id == Screenshots.id(second)
    end

    test "returns a single validation error while keeping accepted screenshots" do
      data = Base.encode64("ok")

      assert {[screenshot], "Unsupported screenshot format. Use PNG, JPEG, WebP, or GIF."} =
               Screenshots.stage([], [
                 %{"data" => data, "media_type" => "image/png"},
                 %{"data" => data, "media_type" => "text/plain"}
               ])

      assert screenshot.media_type == "image/png"
    end

    test "enforces the maximum staged screenshot count" do
      screenshots =
        for index <- 1..7 do
          %{"data" => Base.encode64("image-#{index}"), "media_type" => "image/png"}
        end

      assert {accepted, "Only 6 screenshots can be staged at once."} = Screenshots.stage([], screenshots)
      assert length(accepted) == 6
    end
  end

  test "build/1 rejects oversized screenshots" do
    assert {:error, "Screenshot is too large. Max size is 5 MB."} =
             Screenshots.build(%{"data" => "abc", "media_type" => "image/png", "size" => 5 * 1024 * 1024 + 1})
  end

  test "preview_src/1 returns a data URL" do
    assert Screenshots.preview_src(%{media_type: "image/png", data: "abc"}) == "data:image/png;base64,abc"
  end
end
