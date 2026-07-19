defmodule Tuist.Docs.OgImageTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs
  alias Tuist.Docs.OgImage
  alias Tuist.OpenGraphImages

  test "preserves the existing flattened path and adds its content key" do
    page = Docs.get_page("/en/guides/install-tuist")

    versioned_path = OgImage.image_path(page)

    assert OgImage.slug_to_filename(page.slug) == "en/guides-install-tuist.jpg"
    assert {:versioned, source_path, key} = OpenGraphImages.parse_path(versioned_path)
    assert source_path == "/docs/images/og/generated/en/guides-install-tuist.jpg"
    assert {:ok, %{key: ^key}} = OgImage.resolve(source_path)
  end

  test "keys off the canonical page slug so a non-canonical requested path still resolves" do
    canonical = Docs.get_page("/en/guides/install-tuist")
    # Same page reached via a trailing-slash URL; Docs.get_page/1 normalizes it
    # to the same canonical slug, so both must produce the identical versioned URL.
    normalized = Docs.get_page("/en/guides/install-tuist/")

    assert normalized.slug == canonical.slug
    assert OgImage.image_path(normalized) == OgImage.image_path(canonical)

    {:versioned, source_path, key} = OpenGraphImages.parse_path(OgImage.image_path(normalized))
    assert {:ok, %{key: ^key}} = OgImage.resolve(source_path)
  end
end
