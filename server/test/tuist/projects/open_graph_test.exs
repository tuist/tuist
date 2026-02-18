defmodule Tuist.Projects.OpenGraphTest do
  use ExUnit.Case, async: true

  alias Tuist.Projects.OpenGraph

  test "image_url/4 includes a deterministic hash and encoded params" do
    key_values = [
      %{key: "Duration", value: "4.2s"},
      %{key: "Targets", value: "37"},
      %{key: "Cacheable", value: "28/37"}
    ]

    url_1 = OpenGraph.image_url("tuist", "tuist", "Compilation", key_values)
    url_2 = OpenGraph.image_url("tuist", "tuist", "Compilation", key_values)

    assert url_1 == url_2

    %URI{path: path, query: query} = URI.parse(url_1)

    assert path =~ ~r|/tuist/tuist/og/[0-9a-f]+$|

    assert URI.decode_query(query) == %{
             "title" => "Compilation",
             "k1" => "Duration",
             "v1" => "4.2s",
             "k2" => "Targets",
             "v2" => "37",
             "k3" => "Cacheable",
             "v3" => "28/37"
           }
  end

  test "payload_from_request/4 validates hash and extracts payload" do
    key_values = [
      %{key: "Duration", value: "4.2s"},
      %{key: "Targets", value: "37"},
      %{key: "Cacheable", value: "28/37"}
    ]

    %URI{path: path, query: query} =
      "tuist"
      |> OpenGraph.image_url("tuist", "Compilation", key_values)
      |> URI.parse()

    [_, hash] = Regex.run(~r|/og/([0-9a-f]+)$|, path)
    params = URI.decode_query(query)

    assert {:ok, payload} = OpenGraph.payload_from_request("tuist", "tuist", hash, params)

    assert payload == %{
             account_handle: "tuist",
             project_handle: "tuist",
             hash: hash,
             title: "Compilation",
             key_values: key_values
           }
  end

  test "payload_from_request/4 returns an error for an invalid hash" do
    assert {:error, :invalid_hash} =
             OpenGraph.payload_from_request("tuist", "tuist", "invalid", %{
               "title" => "Compilation"
             })
  end

  test "render_jpeg/1 generates a jpeg image" do
    payload = %{
      account_handle: "tuist",
      project_handle: "tuist",
      title: "Compilation",
      key_values: [
        %{key: "Duration", value: "4.2s"},
        %{key: "Targets", value: "37"},
        %{key: "Cacheable", value: "28/37"}
      ]
    }

    assert {:ok, image_binary} = OpenGraph.render_jpeg(payload)
    assert byte_size(image_binary) > 10_000
    assert :binary.part(image_binary, 0, 3) == <<255, 216, 255>>
  end

  test "render_jpeg/1 handles long semantic key values without crashing" do
    payload = %{
      account_handle: "tuist",
      project_handle: "tuist",
      title: "TuistInternalApp",
      key_values: [
        %{key: "Bundle Size", value: "31.6 MB"},
        %{key: "Type", value: "XCArchive"},
        %{key: "Branch", value: "feature/caching/with-a-very-long-branch-name"}
      ]
    }

    assert {:ok, image_binary} = OpenGraph.render_jpeg(payload)
    assert byte_size(image_binary) > 10_000
    assert :binary.part(image_binary, 0, 3) == <<255, 216, 255>>
  end
end
