defmodule TuistWeb.Components.HashInputsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Tuist.Xcode.XcodeTarget
  alias TuistWeb.Runs.ModuleCacheTab

  test "renders the effective destination difference despite identical declared destinations" do
    target = %XcodeTarget{destinations: ["iphone", "ipad", "mac"], external_hash: "same"}

    render = fn destinations ->
      target = %{
        target
        | binary_cache_hash_inputs:
            JSON.encode!(%{
              "destinations" => destinations,
              "external" => "same",
              "embedded_product_references" => "embedded"
            })
      }

      render_component(&ModuleCacheTab.subhashes_list/1, target: XcodeTarget.with_hash_inputs(target, :binary_cache))
    end

    broad = render.(["iPad", "iPhone", "mac", "macWithiPadDesign"])
    narrow = render.(["iPad", "iPhone", "macWithiPadDesign"])
    assert broad =~ "iPad, iPhone, mac, macWithiPadDesign"
    assert narrow =~ "iPad, iPhone, macWithiPadDesign"
    refute narrow =~ "iPad, iPhone, mac, macWithiPadDesign"
    assert narrow =~ "embedded"
  end

  test "historical destinations are unavailable while a recorded empty set is known" do
    target = %XcodeTarget{destinations: ["iphone", "mac"]}

    historical =
      render_component(&ModuleCacheTab.subhashes_list/1, target: XcodeTarget.with_hash_inputs(target, :binary_cache))

    assert historical =~ "Hashed destinations"
    assert historical =~ "Unavailable"
    refute historical =~ "iphone"

    empty = %{
      target
      | binary_cache_hash_inputs:
          JSON.encode!(%{"destinations" => [], "embedded_product_references" => "", "hashed_strings" => []})
    }

    empty = XcodeTarget.with_hash_inputs(empty, :binary_cache)
    html = render_component(&ModuleCacheTab.subhashes_list/1, target: empty)
    assert html =~ "None"
    assert html =~ "[]"
    refute html =~ "Unavailable"
  end
end
