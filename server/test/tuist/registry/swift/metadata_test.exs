defmodule Tuist.Registry.Swift.MetadataTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Registry
  alias Tuist.Registry.Swift.Metadata

  setup do
    stub(Registry, :registry_bucket, fn -> "test-bucket" end)
    stub(Registry, :registry_s3_config, fn -> [] end)
    :ok
  end

  test "a CAS conflict re-reads and preserves a competing release" do
    first = %{"releases" => %{}}
    second = %{"releases" => %{"1.0.0" => %{"checksum" => "winner"}}}

    expect(ExAws, :request, fn %{http_method: :get}, _ ->
      {:ok, %{body: JSON.encode!(first), headers: [{"etag", "\"one\""}]}}
    end)

    expect(ExAws, :request, fn %{http_method: :put, headers: headers}, _ ->
      assert headers["if-match"] == "\"one\""
      {:error, {:http_error, 412, %{}}}
    end)

    expect(ExAws, :request, fn %{http_method: :get}, _ ->
      {:ok, %{body: JSON.encode!(second), headers: [{"etag", "\"two\""}]}}
    end)

    expect(ExAws, :request, fn %{http_method: :put, body: body, headers: headers}, _ ->
      send(self(), {:written, JSON.decode!(body), headers})
      {:ok, %{}}
    end)

    assert :ok =
             Metadata.update_package("a", "b", first, fn current ->
               {:ok, Map.put(current, "repository_full_handle", "a/b")}
             end)

    assert_receive {:written, written, headers}
    assert written["releases"]["1.0.0"]["checksum"] == "winner"
    assert written["repository_full_handle"] == "a/b"
    assert headers["if-match"] == "\"two\""
  end

  test "a changed checksum is rejected against the current object before writing" do
    current = %{"releases" => %{"1.0.0" => %{"checksum" => "winner"}}}

    expect(ExAws, :request, fn %{http_method: :get}, _ ->
      {:ok, %{body: JSON.encode!(current), headers: %{"etag" => "one"}}}
    end)

    assert {:error, :checksum_changed} =
             Metadata.update_package("a", "b", %{}, fn metadata ->
               if metadata["releases"]["1.0.0"]["checksum"] != "loser", do: {:error, :checksum_changed}
             end)
  end
end
