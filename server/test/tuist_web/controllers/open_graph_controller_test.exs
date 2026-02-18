defmodule TuistWeb.OpenGraphControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Projects.OpenGraph
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    account = AccountsFixtures.account_fixture()
    project = ProjectsFixtures.project_fixture(account: account, visibility: :public, preload: [:account])

    %{account: account, project: project}
  end

  describe "show/2" do
    test "streams the cached image from storage when it exists", %{conn: conn, account: account, project: project} do
      image_url =
        OpenGraph.image_url(account.name, project.name, "Compilation", [
          %{key: "Duration", value: "4.2s"},
          %{key: "Targets", value: "37"},
          %{key: "Cacheable", value: "28/37"}
        ])

      uri = URI.parse(image_url)
      [_, hash] = Regex.run(~r|/og/([0-9a-f]+)$|, uri.path)
      expected_key = "og/#{account.name}/#{project.name}/#{hash}.jpg"

      expect(Storage, :object_exists?, fn ^expected_key, _actor ->
        true
      end)

      expect(Storage, :stream_object, fn ^expected_key, _actor ->
        ["chunk-1", "chunk-2"]
      end)

      conn = get(conn, uri.path <> "?" <> uri.query)

      assert conn.status == 200
      assert conn.state == :chunked
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end

    test "returns 404 when the hash is invalid", %{conn: conn, account: account, project: project} do
      image_url =
        OpenGraph.image_url(account.name, project.name, "Compilation", [
          %{key: "Duration", value: "4.2s"}
        ])

      uri = URI.parse(image_url)
      invalid_path = String.replace(uri.path, ~r/[0-9a-f]+$/, "invalid")

      stub(Storage, :object_exists?, fn _object_key, _actor ->
        flunk("object_exists?/2 should not be called for invalid hashes")
      end)

      conn = get(conn, invalid_path <> "?" <> uri.query)

      assert conn.status == 404
      assert conn.resp_body == ""
    end

    test "generates and persists image when cache is missing", %{conn: conn, account: account, project: project} do
      image_url =
        OpenGraph.image_url(account.name, project.name, "Compilation", [
          %{key: "Duration", value: "4.2s"},
          %{key: "Targets", value: "37"},
          %{key: "Cacheable", value: "28/37"}
        ])

      uri = URI.parse(image_url)
      [_, hash] = Regex.run(~r|/og/([0-9a-f]+)$|, uri.path)
      expected_key = "og/#{account.name}/#{project.name}/#{hash}.jpg"

      expect(Storage, :object_exists?, fn ^expected_key, _actor ->
        false
      end)

      expect(Storage, :put_object, fn ^expected_key, content, _actor ->
        assert byte_size(content) > 10_000
        assert :binary.part(content, 0, 3) == <<255, 216, 255>>
        :ok
      end)

      stub(Storage, :stream_object, fn _object_key, _actor ->
        flunk("stream_object/2 should not be called when generating a new image")
      end)

      conn = get(conn, uri.path <> "?" <> uri.query)

      assert conn.status == 200
      assert conn.state == :chunked
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end
  end
end
