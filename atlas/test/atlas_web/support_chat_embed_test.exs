defmodule AtlasWeb.SupportChatEmbedTest do
  use ExUnit.Case, async: true

  alias AtlasWeb.SupportChatEmbed

  test "uses configured parent origins for the chat frame and messages" do
    parent_origins = ["https://tuist.dev", "http://localhost:8275"]

    assert SupportChatEmbed.parent_origin("http://localhost:8275", parent_origins) ==
             "http://localhost:8275"

    assert SupportChatEmbed.parent_origin("https://example.com", parent_origins) == nil

    assert SupportChatEmbed.frame_ancestors(parent_origins) ==
             "frame-ancestors 'self' https://tuist.dev http://localhost:8275"
  end
end
