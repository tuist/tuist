defmodule Tuist.Kura.VolumeKeys.KMSHTTPTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.VolumeKeys.KMSHTTP

  test "verifies TLS, bounds timeouts and refuses redirects without shared HTTP telemetry" do
    expect(:httpc, :request, fn :post, {url, headers, type, body}, options, response_options ->
      assert url == ~c"https://kms.eu-central-1.amazonaws.com/"
      assert headers == [{~c"authorization", ~c"signature"}]
      assert type == ~c"application/x-amz-json-1.1"
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

    assert KMSHTTP.post(
             "https://kms.eu-central-1.amazonaws.com/",
             [{"authorization", "signature"}],
             "application/x-amz-json-1.1",
             "sensitive request"
           ) == {:ok, "sensitive response"}
  end

  test "provider errors and exceptions are sanitized without logging bodies" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        stub(:httpc, :request, fn _, _, _, _ -> {:ok, {{~c"HTTP/1.1", 403, ~c"Forbidden"}, [], "secret response"}} end)

        assert KMSHTTP.post("https://kms.eu-central-1.amazonaws.com/", [], "application/json", "secret request") ==
                 {:error, :kms_unavailable}

        stub(:httpc, :request, fn _, _, _, _ -> raise "secret exception" end)

        assert KMSHTTP.post("https://kms.eu-central-1.amazonaws.com/", [], "application/json", "secret request") ==
                 {:error, :kms_unavailable}
      end)

    refute log =~ "secret"
  end
end
