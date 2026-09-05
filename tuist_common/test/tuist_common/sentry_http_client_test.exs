defmodule TuistCommon.SentryHTTPClientTest do
  use ExUnit.Case, async: false

  alias TuistCommon.SentryHTTPClient

  @primary_url "https://sentry.example.com/api/42/envelope/"
  @primary_headers [
    {"User-Agent", "sentry-elixir/1.0"},
    {"X-Sentry-Auth",
     "Sentry sentry_version=7, sentry_client=sentry-elixir/1.0, sentry_timestamp=1700000000, sentry_key=primarypublic, sentry_secret=primarysecret"}
  ]

  setup do
    original = Application.get_env(:tuist_common, SentryHTTPClient)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:tuist_common, SentryHTTPClient)
      else
        Application.put_env(:tuist_common, SentryHTTPClient, original)
      end

      Process.delete(:sentry_http_client_test_reroute)
    end)

    :ok
  end

  defp configure_reroute(target) do
    Process.put(:sentry_http_client_test_reroute, target)

    Application.put_env(:tuist_common, SentryHTTPClient, reroute: {__MODULE__, :test_reroute, []})
  end

  def test_reroute, do: Process.get(:sentry_http_client_test_reroute)

  describe "apply_reroute/2" do
    test "passes {url, headers} through when no reroute callback is configured" do
      Application.delete_env(:tuist_common, SentryHTTPClient)

      assert SentryHTTPClient.apply_reroute(@primary_url, @primary_headers) ==
               {@primary_url, @primary_headers}
    end

    test "passes {url, headers} through when the reroute callback returns nil" do
      configure_reroute(nil)

      assert SentryHTTPClient.apply_reroute(@primary_url, @primary_headers) ==
               {@primary_url, @primary_headers}
    end

    test "rewrites URL and X-Sentry-Auth keys when a target with a secret is returned" do
      configure_reroute(%{
        endpoint_uri: "https://hive.tuist.dev/api/3/envelope/",
        public_key: "hivepublic",
        secret_key: "hivesecret"
      })

      {url, headers} = SentryHTTPClient.apply_reroute(@primary_url, @primary_headers)

      assert url == "https://hive.tuist.dev/api/3/envelope/"

      assert {"X-Sentry-Auth", auth} = List.keyfind(headers, "X-Sentry-Auth", 0)
      assert auth =~ "sentry_key=hivepublic"
      assert auth =~ "sentry_secret=hivesecret"
      refute auth =~ "sentry_key=primarypublic"
      refute auth =~ "sentry_secret=primarysecret"
      assert auth =~ "sentry_version=7"
      assert auth =~ "sentry_timestamp=1700000000"
    end

    test "drops sentry_secret entirely when the target only has a public key" do
      configure_reroute(%{
        endpoint_uri: "https://hive.tuist.dev/api/3/envelope/",
        public_key: "hivepublic",
        secret_key: nil
      })

      {_url, headers} = SentryHTTPClient.apply_reroute(@primary_url, @primary_headers)

      assert {"X-Sentry-Auth", auth} = List.keyfind(headers, "X-Sentry-Auth", 0)
      assert auth =~ "sentry_key=hivepublic"
      refute auth =~ "sentry_secret="
    end

    test "leaves non-Sentry headers untouched during a reroute" do
      configure_reroute(%{
        endpoint_uri: "https://hive.tuist.dev/api/3/envelope/",
        public_key: "hivepublic",
        secret_key: nil
      })

      {_url, headers} = SentryHTTPClient.apply_reroute(@primary_url, @primary_headers)

      assert {"User-Agent", "sentry-elixir/1.0"} in headers
    end
  end
end
