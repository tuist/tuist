defmodule Tuist.Docs.OgImageTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs
  alias Tuist.Docs.OgImage
  alias Tuist.OpenGraphImages

  test "preserves the existing flattened path and adds its content key" do
    slug = "/en/guides/install-tuist"
    page = Docs.get_page(slug)

    versioned_path = OgImage.image_path(slug, page)

    assert OgImage.slug_to_filename(slug) == "en/guides-install-tuist.jpg"
    assert {:versioned, source_path, key} = OpenGraphImages.parse_path(versioned_path)
    assert source_path == "/docs/images/og/generated/en/guides-install-tuist.jpg"
    assert {:ok, %{key: ^key}} = OgImage.resolve(source_path)
  end
end
