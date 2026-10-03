defmodule Tuist.OpenGraphImageTemplatesTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Marketing.Blog.CoverArtwork, as: BlogCoverArtwork
  alias Tuist.OpenGraphImageTemplates

  test "builds deterministic specs from template variables" do
    params = %{
      "template" => "docs",
      "title" => "Install Tuist",
      "description" => "Install the command-line interface.",
      "category" => "Guides"
    }

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(params)
    assert {:ok, second_spec} = OpenGraphImageTemplates.spec(params)
    assert first_spec.key == second_spec.key
    assert first_spec.params == params
  end

  test "changes the content key when a template variable changes" do
    assert {:ok, first_spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing",
               "title" => "About Tuist"
             })

    assert {:ok, second_spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing",
               "title" => "Pricing"
             })

    refute first_spec.key == second_spec.key
  end

  test "rejects unknown template variables" do
    assert OpenGraphImageTemplates.spec(%{
             "template" => "marketing",
             "title" => "About Tuist",
             "source_path" => "/arbitrary"
           }) == :error
  end

  test "builds deterministic case study specs from the cover artwork" do
    params = %{"template" => "marketing_case_study", "slug" => "monzo"}

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(params)
    assert {:ok, second_spec} = OpenGraphImageTemplates.spec(params)
    assert first_spec.key == second_spec.key

    assert {:ok, other_spec} =
             OpenGraphImageTemplates.spec(%{"template" => "marketing_case_study", "slug" => "trendyol"})

    refute first_spec.key == other_spec.key
  end

  test "rejects case studies without cover artwork and unsafe slugs" do
    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_case_study", "slug" => "unknown-company"}) ==
             :error

    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_case_study", "slug" => "../secrets"}) ==
             :error
  end

  test "rejects blog covers without artwork and unsafe slugs" do
    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "no-such-post"}) ==
             :error

    assert OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "../secrets"}) ==
             :error
  end

  test "keys blog cover images by the artwork" do
    stub(BlogCoverArtwork, :available?, fn slug -> slug in ["one", "two"] end)
    stub(BlogCoverArtwork, :svg, fn slug, :og -> ~s(<svg data-part="artwork">#{slug}</svg>) end)

    assert {:ok, first_spec} = OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "one"})
    assert {:ok, again_spec} = OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "one"})
    assert {:ok, other_spec} = OpenGraphImageTemplates.spec(%{"template" => "marketing_blog_cover", "slug" => "two"})

    assert first_spec.key == again_spec.key
    refute first_spec.key == other_spec.key
  end

  test "renders text-only images as JPEG data" do
    assert {:ok, spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing_text",
               "title" => "A runtime-generated image"
             })

    assert {:ok, <<0xFF, 0xD8, _rest::binary>>} = spec.render.()
  end
end
