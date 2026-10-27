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
      render_component(&ModuleCacheTab.subhashes_list/1,
        target: %{target | hashed_destinations: destinations},
        show_test_destination: true
      )
    end

    broad = render.(["iPad", "iPhone", "mac", "macWithiPadDesign"])
    narrow = render.(["iPad", "iPhone", "macWithiPadDesign"])
    assert broad =~ "iPad, iPhone, mac, macWithiPadDesign"
    assert narrow =~ "iPad, iPhone, macWithiPadDesign"
    refute narrow =~ "iPad, iPhone, mac, macWithiPadDesign"
    for value <- ["embedded", "foreign", "iPhone 16", "iOS-16"], do: assert(narrow =~ value)
  end

  test "only selective testing details expose the test destination" do
    target = %XcodeTarget{test_device: "iPhone 16", test_runtime: "iOS-16"}
    module_cache = render_component(&ModuleCacheTab.subhashes_list/1, target: target)
    selective_testing = render_component(&ModuleCacheTab.subhashes_list/1, target: target, show_test_destination: true)

    for value <- ["Test device", "Test runtime", "iPhone 16", "iOS-16"] do
      refute module_cache =~ value
      assert selective_testing =~ value
    end
  end

  test "historical destinations are unavailable while recorded empty inputs are known" do
    target = %XcodeTarget{destinations: ["iphone", "mac"], hashed_destinations: nil}
    historical = render_component(&ModuleCacheTab.subhashes_list/1, target: target)
    assert historical =~ "Destinations"
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

  test "lists direct dependencies as sorted links while retaining the aggregate hash" do
    target = %XcodeTarget{dependencies: ["Networking", "Core"], dependencies_hash: "dependency-content-hash"}
    project = %{name: "app", account: %{name: "team"}}
    html = render_component(&ModuleCacheTab.subhashes_list/1, target: target, project: project)
    document = Floki.parse_fragment!(html)
    links = Floki.find(document, "[data-part=dependency-link]")

    assert links |> Enum.map(&Floki.text/1) |> Enum.map(&String.trim/1) == ["Core", "Networking"]

    assert Floki.attribute(links, "href") == [
             "/team/app/module-cache/modules/Core",
             "/team/app/module-cache/modules/Networking"
           ]

    assert html =~ "Dependencies hash"
    assert html =~ "dependency-content-hash"
  end

  test "describes missing dependency names without implying that the aggregate hash is empty" do
    html = render_component(&ModuleCacheTab.subhashes_list/1, target: %XcodeTarget{dependencies_hash: "sdk-hash"})
    assert html =~ "No direct target dependencies recorded"
    assert html =~ "sdk-hash"
  end
end
