defmodule Atlas.Documents.EmbeddingTest do
  use ExUnit.Case, async: true

  alias Atlas.Documents.Embedding

  describe "embed/2 with the configured client" do
    test "delegates to the configured embedding client (the test stub)" do
      assert {:ok, %{model: "test-embedding", embedding: embedding}} = Embedding.embed("hello")
      assert length(embedding) == 1536
    end
  end

  describe "embed/2 over HTTP" do
    test "returns the embedding on success and builds the request" do
      req = fn %Req.Request{} = request ->
        assert request.method == :post
        assert URI.to_string(request.url) == "https://llm.example/v1/embeddings"
        assert {:bearer, "secret"} = request.options.auth
        assert request.options.json == %{model: "custom-model", input: "hello"}

        {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => [0.1, 0.2, 0.3]}]}}}
      end

      assert {:ok, %{model: "custom-model", embedding: [0.1, 0.2, 0.3]}} =
               Embedding.embed("hello",
                 client: nil,
                 api_key: "secret",
                 base_url: "https://llm.example/v1/",
                 model: "custom-model",
                 req: req
               )
    end

    test "bounds long HTTP embedding inputs for short-context providers" do
      long_input = 1..500 |> Enum.map_join(" ", &"term#{&1}")

      req = fn %Req.Request{} = request ->
        input = request.options.json.input

        assert length(String.split(input, " ", trim: true)) <= 200
        assert String.length(input) <= 1_000
        assert input =~ "term1"
        refute input =~ "term500"

        {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => [0.1]}]}}}
      end

      assert {:ok, %{model: "custom-model", embedding: [0.1]}} =
               Embedding.embed(long_input,
                 client: nil,
                 api_key: "secret",
                 base_url: "https://llm.example/v1/",
                 model: "custom-model",
                 req: req
               )
    end

    test "retries with a stricter bound when the provider rejects the context length" do
      test_pid = self()
      long_input = 1..500 |> Enum.map_join(" ", &"term#{&1}")

      req = fn %Req.Request{} = request ->
        input = request.options.json.input
        send(test_pid, {:embedding_input, input})

        if String.length(input) > 500 do
          {:ok,
           %Req.Response{
             status: 400,
             body: %{
               "error" => %{
                 "message" => "This model's maximum context length is 512 tokens."
               }
             }
           }}
        else
          {:ok, %Req.Response{status: 200, body: %{"data" => [%{"embedding" => [0.2]}]}}}
        end
      end

      assert {:ok, %{model: "custom-model", embedding: [0.2]}} =
               Embedding.embed(long_input,
                 client: nil,
                 api_key: "secret",
                 base_url: "https://llm.example/v1/",
                 model: "custom-model",
                 req: req
               )

      assert_receive {:embedding_input, first_input}
      assert_receive {:embedding_input, second_input}
      assert String.length(first_input) <= 1_000
      assert String.length(second_input) <= 500
    end

    test "returns an error tuple for a non-success status" do
      req = fn _request -> {:ok, %Req.Response{status: 401, body: %{"error" => "bad key"}}} end

      assert {:error, {:embedding_request_failed, 401, %{"error" => "bad key"}}} =
               Embedding.embed("hello", client: nil, api_key: "secret", req: req)
    end

    test "returns an error tuple for an unexpected body shape" do
      req = fn _request -> {:ok, %Req.Response{status: 200, body: %{"unexpected" => true}}} end

      assert {:error, {:embedding_request_failed, 200, %{"unexpected" => true}}} =
               Embedding.embed("hello", client: nil, api_key: "secret", req: req)
    end

    test "propagates transport errors" do
      req = fn _request -> {:error, :timeout} end

      assert {:error, :timeout} = Embedding.embed("hello", client: nil, api_key: "secret", req: req)
    end

    test "returns :embedding_not_configured without an api key" do
      req = fn _request -> flunk("should not perform a request when unconfigured") end

      assert {:error, :embedding_not_configured} =
               Embedding.embed("hello", client: nil, api_key: "", req: req)
    end
  end

  describe "configured_model/0" do
    test "returns the configured embedding model" do
      # runtime.exs sets this for every env (default when the env var is unset).
      assert Embedding.configured_model() == "text-embedding-3-small"
    end
  end
end
