defmodule Tuist.Kura.VolumeKeys.KeyServiceHTTPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.VolumeKeys.KeyServiceHTTP

  test "verifies TLS, bounds timeouts and refuses redirects without shared HTTP telemetry" do
    expect(:httpc, :request, fn :post, {url, headers, type, body}, options, response_options ->
      assert url == ~c"https://openbao.example.test/v1/transit/encrypt/kura-volume-root"
      assert headers == [{~c"X-Vault-Token", ~c"workload-token"}]
      assert type == ~c"application/json"
      assert body == "sensitive request"
      assert options[:timeout] == 5_000
      assert options[:connect_timeout] == 3_000
      assert options[:autoredirect] == false
      assert options[:ssl][:verify] == :verify_peer
      assert options[:ssl][:cacerts] != []
      assert is_function(options[:ssl][:customize_hostname_check][:match_fun], 2)
      assert response_options == [body_format: :binary]
      {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], "sensitive response"}}
    end)

    assert KeyServiceHTTP.post(
             "https://openbao.example.test/v1/transit/encrypt/kura-volume-root",
             [{"X-Vault-Token", "workload-token"}],
             "application/json",
             "sensitive request"
           ) == {:ok, "sensitive response"}
  end

  test "a private CA retains peer and hostname verification" do
    expect(:httpc, :request, fn :post, _, options, _ ->
      assert options[:ssl][:cacertfile] == ~c"/test/openbao-ca.pem"
      assert options[:ssl][:verify] == :verify_peer
      refute Keyword.has_key?(options[:ssl], :cacerts)
      assert is_function(options[:ssl][:customize_hostname_check][:match_fun], 2)
      {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], "{}"}}
    end)

    assert {:ok, "{}"} =
             KeyServiceHTTP.post("https://openbao.test/", [], "application/json", "{}", "/test/openbao-ca.pem")
  end

  test "provider errors and exceptions are sanitized without logging bodies" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        stub(:httpc, :request, fn _, _, _, _ -> {:ok, {{~c"HTTP/1.1", 403, ~c"Forbidden"}, [], "secret response"}} end)

        assert KeyServiceHTTP.post(
                 "https://openbao.example.test/v1/transit/encrypt/kura-volume-root",
                 [],
                 "application/json",
                 "secret request"
               ) ==
                 {:error, :key_service_unavailable}

        stub(:httpc, :request, fn _, _, _, _ -> raise "secret exception" end)

        assert KeyServiceHTTP.post(
                 "https://openbao.example.test/v1/transit/encrypt/kura-volume-root",
                 [],
                 "application/json",
                 "secret request"
               ) ==
                 {:error, :key_service_unavailable}
      end)

    refute log =~ "secret"
  end
end
