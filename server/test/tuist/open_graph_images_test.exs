defmodule Tuist.OpenGraphImagesTest do
  use ExUnit.Case, async: true

  alias Tuist.OpenGraphImages

  describe "key/1" do
    test "is deterministic and changes with the rendering attributes" do
      assert OpenGraphImages.key(["page", "English", "Title"]) ==
               OpenGraphImages.key(["page", "English", "Title"])

      refute OpenGraphImages.key(["page", "English", "Title"]) ==
               OpenGraphImages.key(["page", "English", "Different title"])
    end
  end

  describe "versioned paths" do
    test "adds and parses the content key" do
      key = String.duplicate("a", 64)
      source_path = "/marketing/images/og/generated/about.jpg"
      versioned_path = "/marketing/images/og/generated/about-#{key}.jpg"

      assert OpenGraphImages.versioned_path(source_path, key) == versioned_path
      assert OpenGraphImages.parse_path(versioned_path) == {:versioned, source_path, key}
      assert OpenGraphImages.parse_path(source_path) == {:unversioned, source_path}
    end
  end
end
