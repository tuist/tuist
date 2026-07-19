defmodule TuistWeb.OpenGraphImageControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.Marketing.OpenGraphImage, as: MarketingImage
  alias Tuist.OpenGraphImageRenderer
  alias Tuist.OpenGraphImages
  alias Tuist.Storage

  setup do
    stub(Environment, :tuist_hosted?, fn -> true end)
    :ok
  end

  test "redirects an unversioned image path to its content-addressed path", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)

    conn = get(conn, source_path)

    assert redirected_to(conn) == OpenGraphImages.versioned_path(source_path, spec.key)
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
  end

  test "streams a cached image without rendering it again", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)
    versioned_path = OpenGraphImages.versioned_path(source_path, spec.key)
    object_key = "open-graph-images/#{spec.key}.jpg"

    expect(Storage, :object_exists?, fn ^object_key, :open_graph_images -> true end)
    expect(Storage, :stream_object, fn ^object_key, :open_graph_images -> ["cached-image"] end)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, versioned_path)

    assert response(conn, :ok) == "cached-image"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(conn, "etag") == [~s("#{spec.key}")]
  end

  test "renders and stores an image on the first request", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)
    versioned_path = OpenGraphImages.versioned_path(source_path, spec.key)
    object_key = "open-graph-images/#{spec.key}.jpg"

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" -> {:ok, "generated-image"} end)

    expect(Storage, :put_object, fn ^object_key, "generated-image", :open_graph_images ->
      :ok
    end)

    expect(Storage, :stream_object, fn ^object_key, :open_graph_images -> ["generated-image"] end)

    conn = get(conn, versioned_path)

    assert response(conn, :ok) == "generated-image"
  end

  test "serves a fallback image transiently without persisting it", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)
    versioned_path = OpenGraphImages.versioned_path(source_path, spec.key)
    object_key = "open-graph-images/#{spec.key}.jpg"

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" -> {:fallback, "fallback-image"} end)
    reject(&Storage.put_object/3)
    reject(&Storage.stream_object/2)

    conn = get(conn, versioned_path)

    assert response(conn, :ok) == "fallback-image"
    assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
    assert get_resp_header(conn, "etag") == []
  end

  test "returns service unavailable when generation exits", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)
    versioned_path = OpenGraphImages.versioned_path(source_path, spec.key)
    object_key = "open-graph-images/#{spec.key}.jpg"

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)

    expect(OpenGraphImageRenderer, :render, fn _html, "About Tuist" ->
      exit({:timeout, {GenServer, :call, [OpenGraphImageRenderer, :ensure_pool, 60_000]}})
    end)

    conn = get(conn, versioned_path)

    assert response(conn, :service_unavailable) == ""
  end

  test "returns not found for a stale content key that is absent from storage", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    stale_key = String.duplicate("0", 64)
    versioned_path = OpenGraphImages.versioned_path(source_path, stale_key)
    object_key = "open-graph-images/#{stale_key}.jpg"

    expect(Storage, :object_exists?, 2, fn ^object_key, :open_graph_images -> false end)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, versioned_path)

    assert response(conn, :not_found) == ""
    assert get_resp_header(conn, "cache-control") == ["public, max-age=60"]
  end

  test "honors the entity tag without downloading the cached image", %{conn: conn} do
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)
    versioned_path = OpenGraphImages.versioned_path(source_path, spec.key)
    object_key = "open-graph-images/#{spec.key}.jpg"

    expect(Storage, :object_exists?, fn ^object_key, :open_graph_images -> true end)
    reject(&Storage.stream_object/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = conn |> put_req_header("if-none-match", ~s("#{spec.key}")) |> get(versioned_path)

    assert response(conn, :not_modified) == ""
  end

  test "does not render on-premise, forwarding the request away instead", %{conn: conn} do
    stub(Environment, :tuist_hosted?, fn -> false end)
    source_path = "/marketing/images/og/generated/about.jpg"
    {:ok, spec} = MarketingImage.resolve(source_path)
    versioned_path = OpenGraphImages.versioned_path(source_path, spec.key)

    reject(&Storage.object_exists?/2)
    reject(&OpenGraphImageRenderer.render/2)

    conn = get(conn, versioned_path)

    assert conn.status in [301, 302]
    assert conn.halted
  end
end
