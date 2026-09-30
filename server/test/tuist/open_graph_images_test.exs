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

  describe "spec/3" do
    test "keeps the signed template variables with the render function" do
      params = %{"template" => "marketing", "title" => "About Tuist"}
      render = fn -> {:ok, "image"} end

      spec = OpenGraphImages.spec(["marketing", "About Tuist"], params, render)

      assert spec.params == params
      assert spec.render == render
      assert spec.key == OpenGraphImages.key(["marketing", "About Tuist"])
    end
  end
end
