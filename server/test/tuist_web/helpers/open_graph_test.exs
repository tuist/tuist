defmodule TuistWeb.Helpers.OpenGraphTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.OpenGraph

  test "builds a deterministic path with visible signed template variables" do
    first_path =
      OpenGraph.image_path(:marketing,
        title: "About Tuist",
        icon: "static/marketing/images/about/logo.webp"
      )

    second_path =
      OpenGraph.image_path(:marketing,
        icon: "static/marketing/images/about/logo.webp",
        title: "About Tuist"
      )

    assert first_path == second_path

    uri = URI.parse(first_path)
    params = URI.decode_query(uri.query)
    signature = Map.fetch!(params, "signature")
    image_params = Map.delete(params, "signature")

    assert uri.path =~ ~r|\A/open-graph-images/[0-9a-f]{64}\.jpg\z|

    assert image_params == %{
             "icon" => "static/marketing/images/about/logo.webp",
             "template" => "marketing",
             "title" => "About Tuist"
           }

    assert OpenGraph.verify_image_params(image_params, signature) == :ok
  end

  test "rejects a signature after a template variable changes" do
    path = OpenGraph.image_path(:marketing, title: "About Tuist")
    params = path |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    signature = Map.fetch!(params, "signature")

    image_params =
      params
      |> Map.delete("signature")
      |> Map.put("title", "Pricing")

    assert OpenGraph.verify_image_params(image_params, signature) == :error
  end

  test "rejects a non-binary signature" do
    assert OpenGraph.verify_image_params(%{"template" => "marketing"}, ["invalid"]) == :error
  end
end
