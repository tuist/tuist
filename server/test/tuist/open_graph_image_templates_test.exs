defmodule Tuist.OpenGraphImageTemplatesTest do
  use ExUnit.Case, async: true

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

  test "renders text-only images as JPEG data" do
    assert {:ok, spec} =
             OpenGraphImageTemplates.spec(%{
               "template" => "marketing_text",
               "title" => "A runtime-generated image"
             })

    assert {:ok, <<0xFF, 0xD8, _rest::binary>>} = spec.render.()
  end
end
