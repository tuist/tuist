defmodule TuistWeb.Components.HashInputsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Xcode.XcodeTarget
  alias TuistWeb.Runs.ModuleCacheTab

  test "renders effective destination differences despite identical declared destinations" do
    target = %XcodeTarget{
      destinations: ["iphone", "ipad", "mac"],
      external_hash: "same",
      embedded_product_references_hash: "embedded",
      foreign_build_hash: "foreign",
      test_device: "iPhone 16",
      test_runtime: "iOS-16"
    }

    render = fn destinations ->
      render_component(&ModuleCacheTab.subhashes_list/1, target: %{target | hashed_destinations: destinations})
    end

    broad = render.(["iPad", "iPhone", "mac", "macWithiPadDesign"])
    narrow = render.(["iPad", "iPhone", "macWithiPadDesign"])
    assert broad =~ "iPad, iPhone, mac, macWithiPadDesign"
    assert narrow =~ "iPad, iPhone, macWithiPadDesign"
    refute narrow =~ "iPad, iPhone, mac, macWithiPadDesign"
    for value <- ["embedded", "foreign", "iPhone 16", "iOS-16"], do: assert(narrow =~ value)
  end

  test "historical destinations are unavailable while recorded empty inputs are known" do
    target = %XcodeTarget{destinations: ["iphone", "mac"], hashed_destinations: nil}
    historical = render_component(&ModuleCacheTab.subhashes_list/1, target: target)
    assert historical =~ "Hashed destinations"
    assert historical =~ "Unavailable"
    refute historical =~ "iphone"

    empty = %{
      target
      | hashed_destinations: [],
        embedded_product_references_hash: "",
        foreign_build_hash: "",
        test_device: "",
        test_runtime: ""
    }

    html = render_component(&ModuleCacheTab.subhashes_list/1, target: empty)
    assert html =~ "None"
    refute html =~ "Unavailable"
  end
end
