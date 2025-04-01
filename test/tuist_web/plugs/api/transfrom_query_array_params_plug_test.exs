defmodule TuistWeb.API.TransformQueryArrayParamsPlugTest do
  alias TuistWeb.Plugs.API.TransformQueryArrayParamsPlug
  use TuistTestSupport.Cases.ConnCase
  import Plug.Test

  test "updates query_params when there is only one element" do
    # Given
    opts = TransformQueryArrayParamsPlug.init([:platforms])
    conn = build_conn(:get, ~p"/api/previews?platforms=ios")
    # display_name=App&specifier=latest&page_size=1&supported_platforms=ios
    # When
    conn = conn |> TransformQueryArrayParamsPlug.call(opts)

    # Then
    assert conn.query_params == %{"platforms" => ["ios"]}
  end

  test "updates query_params when there are multiple elements" do
    # Given
    opts = TransformQueryArrayParamsPlug.init([:platforms])
    conn = build_conn(:get, ~p"/api/previews?platforms=ios&platforms=macos")
    # When
    conn = conn |> TransformQueryArrayParamsPlug.call(opts)

    # Then
    assert conn.query_params == %{"platforms" => ["ios", "macos"]}
  end

  test "updates query_params when there are multiple elements and the query includes extra values" do
    # Given
    opts = TransformQueryArrayParamsPlug.init([:platforms])
    conn = build_conn(:get, ~p"/api/previews?platforms=ios&platforms=macos&unrelated_value=foo")

    # When
    conn = conn |> TransformQueryArrayParamsPlug.call(opts)

    # Then
    assert conn.query_params == %{"platforms" => ["ios", "macos"], "unrelated_value" => "foo"}
  end

  test "does not query_params when the query has only unrelated values" do
    # Given
    opts = TransformQueryArrayParamsPlug.init([:platforms])
    conn = build_conn(:get, ~p"/api/previews?unrelated_value=foo")

    # When
    conn = conn |> TransformQueryArrayParamsPlug.call(opts)

    # Then
    assert conn.query_params == %{"unrelated_value" => "foo"}
  end

  test "does not query_params when there is no query" do
    # Given
    opts = TransformQueryArrayParamsPlug.init([:platforms])
    conn = build_conn(:get, ~p"/api/previews")

    # When
    conn = conn |> TransformQueryArrayParamsPlug.call(opts)

    # Then
    assert conn.query_params == %{}
  end
end
