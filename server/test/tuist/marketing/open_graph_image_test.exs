defmodule Tuist.Marketing.OpenGraphImageTest do
  use ExUnit.Case, async: true

  alias Tuist.Marketing.Blog
  alias Tuist.Marketing.Newsletter
  alias Tuist.Marketing.OpenGraphImage

  describe "resolve/1" do
    test "renders blog images through libvips as a plain {:ok, binary}" do
      post = Enum.find(Blog.get_posts(), &is_nil(&1.og_image_path))

      {:ok, spec} = OpenGraphImage.resolve("/marketing/images/og/generated#{post.slug}.jpg")

      assert {:ok, <<0xFF, 0xD8, _rest::binary>>} = spec.render.()
    end

    test "renders newsletter issue images through libvips as a plain {:ok, binary}" do
      issue = List.first(Newsletter.issues())

      {:ok, spec} = OpenGraphImage.resolve("/marketing/images/og/generated/newsletter/issues/#{issue.number}.jpg")

      assert {:ok, <<0xFF, 0xD8, _rest::binary>>} = spec.render.()
    end

    test "does not resolve a blog post that ships its own image" do
      post = Enum.find(Blog.get_posts(), &(not is_nil(&1.og_image_path)))

      assert OpenGraphImage.resolve("/marketing/images/og/generated#{post.slug}.jpg") == :error
    end
  end
end
