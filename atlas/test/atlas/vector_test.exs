defmodule Atlas.VectorTest do
  use ExUnit.Case, async: true

  alias Atlas.Vector

  describe "upsert_vectors/2" do
    test "posts records in OpenData's write format" do
      request = fn %Req.Request{} = request ->
        assert request.method == :post
        assert URI.to_string(request.url) == "http://vector.example/api/v1/vector/write"
        assert request.headers["accept"] == ["application/protobuf+json"]
        assert request.headers["content-type"] == ["application/protobuf+json"]
        assert request.options.receive_timeout == 12_000

        assert request.options.json == %{
                 "upsertVectors" => [
                   %{
                     "id" => "event:123",
                     "attributes" => %{
                       "vector" => [1.0, 0.0],
                       "source_type" => "event",
                       "source_id" => "123"
                     }
                   }
                 ]
               }

        {:ok, %Req.Response{status: 200, body: %{"status" => "success", "vectorsUpserted" => 1}}}
      end

      assert {:ok, %{"vectorsUpserted" => 1}} =
               Vector.upsert_vectors(
                 [
                   %{
                     id: "event:123",
                     vector: [1.0, 0.0],
                     attributes: %{source_type: "event", source_id: "123"}
                   }
                 ],
                 base_url: "http://vector.example",
                 receive_timeout: 12_000,
                 request: request
               )
    end
  end

  describe "search/2" do
    test "posts search options" do
      request = fn %Req.Request{} = request ->
        assert request.method == :post
        assert URI.to_string(request.url) == "http://vector.example/api/v1/vector/search"

        assert request.options.json == %{
                 "vector" => [1.0, 0.0],
                 "k" => 3,
                 "nprobe" => 20,
                 "filter" => %{"eq" => %{"field" => "source_type", "value" => "event"}},
                 "includeFields" => ["source_id"]
               }

        {:ok, %Req.Response{status: 200, body: %{"status" => "success", "results" => []}}}
      end

      assert {:ok, %{"results" => []}} =
               Vector.search([1.0, 0.0],
                 base_url: "http://vector.example",
                 request: request,
                 k: 3,
                 nprobe: 20,
                 filter: %{"eq" => %{"field" => "source_type", "value" => "event"}},
                 include_fields: ["source_id"]
               )
    end
  end

  describe "get_vector/2" do
    test "fetches a vector by encoded ID" do
      request = fn %Req.Request{} = request ->
        assert request.method == :get
        assert URI.to_string(request.url) == "http://vector.example/api/v1/vector/vectors/event%3A123"

        {:ok, %Req.Response{status: 200, body: %{"status" => "success", "vector" => %{"id" => "event:123"}}}}
      end

      assert {:ok, %{"vector" => %{"id" => "event:123"}}} =
               Vector.get_vector("event:123", base_url: "http://vector.example", request: request)
    end
  end

  describe "delete_vectors/2" do
    test "posts IDs to delete" do
      request = fn %Req.Request{} = request ->
        assert request.method == :post
        assert URI.to_string(request.url) == "http://vector.example/api/v1/vector/delete"
        assert request.options.json == %{"ids" => ["event:123"]}

        {:ok, %Req.Response{status: 200, body: %{"status" => "success", "vectorsDeleted" => 1}}}
      end

      assert {:ok, %{"vectorsDeleted" => 1}} =
               Vector.delete_vectors(["event:123"], base_url: "http://vector.example", request: request)
    end
  end

  test "returns :disabled without a base URL" do
    assert :disabled = Vector.search([1.0], base_url: nil)
  end

  test "returns HTTP errors with the response body" do
    request = fn %Req.Request{} ->
      {:ok, %Req.Response{status: 400, body: %{"message" => "bad vector"}}}
    end

    assert {:error, {:http, 400, %{"message" => "bad vector"}}} =
             Vector.search([1.0], base_url: "http://vector.example", request: request)
  end
end
