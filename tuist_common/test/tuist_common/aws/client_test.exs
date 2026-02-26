defmodule TuistCommon.AWS.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistCommon.AWS.Client

  setup :set_mimic_global

  describe "request/5 with connect_options and finch" do
    test "strips connect_options when finch is configured" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, connect_options: [protocols: [:http1]])

      expect(Req, :request, fn opts ->
        refute Keyword.has_key?(opts, :connect_options)
        assert Keyword.get(opts, :finch) == TestFinch

        {:ok, %Req.Response{status: 200, headers: %{}, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} = Client.request(:get, "https://example.com")
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "strips inet6 when finch is configured" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, inet6: true)

      expect(Req, :request, fn opts ->
        refute Keyword.has_key?(opts, :inet6)
        assert Keyword.get(opts, :finch) == TestFinch

        {:ok, %Req.Response{status: 200, headers: %{}, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} = Client.request(:get, "https://example.com")
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "strips connect_options passed via http_opts" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, [])

      http_opts = [connect_options: [protocols: [:http2]], timeout: 5000]

      expect(Req, :request, fn opts ->
        refute Keyword.has_key?(opts, :connect_options)
        assert Keyword.get(opts, :finch) == TestFinch
        assert Keyword.get(opts, :timeout) == 5000

        {:ok, %Req.Response{status: 200, headers: %{}, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} =
               Client.request(:get, "https://example.com", "", [], http_opts)
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "preserves connect_options when no finch is configured" do
      Application.put_env(:tuist_common, :finch_name, nil)
      Application.put_env(:ex_aws, :req_opts, connect_options: [protocols: [:http1]])

      expect(Req, :request, fn opts ->
        assert Keyword.has_key?(opts, :connect_options)
        assert Keyword.get(opts, :finch) == nil

        {:ok, %Req.Response{status: 200, headers: %{}, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} = Client.request(:get, "https://example.com")
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "removes follow_redirect from options" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, [])

      http_opts = [follow_redirect: true]

      expect(Req, :request, fn opts ->
        refute Keyword.has_key?(opts, :follow_redirect)

        {:ok, %Req.Response{status: 200, headers: %{}, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} =
               Client.request(:get, "https://example.com", "", [], http_opts)
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "converts map http_opts to keyword list" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, [])

      http_opts = %{connect_options: [protocols: [:http1]], timeout: 5000}

      expect(Req, :request, fn opts ->
        refute Keyword.has_key?(opts, :connect_options)
        assert Keyword.get(opts, :timeout) == 5000

        {:ok, %Req.Response{status: 200, headers: %{}, body: "ok"}}
      end)

      assert {:ok, %{status_code: 200}} =
               Client.request(:get, "https://example.com", "", [], http_opts)
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "passes method, url, body, and headers correctly" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, [])

      expect(Req, :request, fn opts ->
        assert Keyword.get(opts, :method) == :post
        assert Keyword.get(opts, :url) == "https://s3.example.com/bucket/key"
        assert Keyword.get(opts, :body) == "request body"
        assert Keyword.get(opts, :headers) == [{"authorization", "Bearer token"}]
        assert Keyword.get(opts, :decode_body) == false

        {:ok, %Req.Response{status: 201, headers: %{"etag" => ["abc"]}, body: ""}}
      end)

      assert {:ok, %{status_code: 201, headers: %{"etag" => ["abc"]}}} =
               Client.request(
                 :post,
                 "https://s3.example.com/bucket/key",
                 "request body",
                 [{"authorization", "Bearer token"}]
               )
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end

    test "returns error tuple on request failure" do
      Application.put_env(:tuist_common, :finch_name, TestFinch)
      Application.put_env(:ex_aws, :req_opts, [])

      expect(Req, :request, fn _opts ->
        {:error, %Mint.TransportError{reason: :closed}}
      end)

      assert {:error, %{reason: %Mint.TransportError{reason: :closed}}} =
               Client.request(:get, "https://example.com")
    after
      Application.delete_env(:tuist_common, :finch_name)
      Application.delete_env(:ex_aws, :req_opts)
    end
  end
end
