defmodule TuistEx.Analytics.NetworkTrustedPublishingTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistEx.Analytics.HTTP, as: AnalyticsHTTP
  alias TuistEx.Auth
  alias TuistEx.HTTP

  @moduletag :tmp_dir

  defp options(directory, overrides \\ %{}) do
    values =
      Map.merge(
        %{
          "TUIST_URL" => "https://tuist.example",
          "TUIST_PROJECT" => "acme/widgets",
          "TUIST_NETWORK_TRUSTED_PUBLISHING" => "true",
          "XDG_CONFIG_HOME" => directory,
          "USER" => "developer-123"
        },
        overrides
      )

    [environment: &Map.get(values, &1)]
  end

  test "builds and tests publish without authentication and omit privileged references", %{
    tmp_dir: directory
  } do
    for suffix <- ["/tests", "/mix/builds"] do
      expect(HTTP, :request, fn :post, url, body, headers ->
        assert String.ends_with?(url, suffix)
        refute Enum.any?(headers, fn {key, _} -> key == "authorization" end)
        assert {"x-tuist-actor-id", "developer-123"} in headers
        refute Map.has_key?(body, :git_history)
        refute Map.has_key?(body, :build_run_id)
        {:ok, 200, %{"id" => "server-id"}}
      end)

      assert {:ok, %{"id" => "server-id"}} =
               AnalyticsHTTP.project_request(
                 :post,
                 suffix,
                 %{git_history: %{}, build_run_id: "old-id", duration: 42},
                 options(directory)
               )
    end
  end

  test "reads and shard planning still require credentials", %{tmp_dir: directory} do
    reject(HTTP, :request, 4)

    assert {:error, _} =
             AnalyticsHTTP.project_request(:post, "/tests/shards", %{}, options(directory))

    assert {:error, _} = AnalyticsHTTP.project_request(:get, "/tests", nil, options(directory))
  end

  test "explicit blank credentials never become anonymous", %{tmp_dir: directory} do
    reject(HTTP, :request, 4)

    for token <- ["", "  "] do
      assert {:error, _} =
               AnalyticsHTTP.submit_mix_build(%{}, options(directory, %{"TUIST_TOKEN" => token}))
    end
  end

  test "supplied credentials retain authenticated publishing", %{tmp_dir: directory} do
    expect(HTTP, :request, fn :post, _url, _body, headers ->
      assert {"authorization", "Bearer supplied-token"} in headers
      {:ok, 201, %{}}
    end)

    assert :ok =
             AnalyticsHTTP.submit_mix_build(
               %{},
               options(directory, %{"TUIST_TOKEN" => "supplied-token"})
             )
  end

  test "corrupt, blank, null, and missing-access credentials fail closed without deleting files",
       %{tmp_dir: directory} do
    path = Path.join([directory, "tuist", "credentials", "tuist.example.json"])
    File.mkdir_p!(Path.dirname(path))
    reject(HTTP, :request, 4)

    for contents <- [
          "not json",
          "null",
          "[]",
          "{}",
          ~s({"accessToken":""}),
          ~s({"accessToken":"  "}),
          ~s({"accessToken":"expired","rejected":true})
        ] do
      File.write!(path, contents)
      assert {:error, _} = Auth.reporting_token(options(directory))
      assert File.read!(path) == contents
      assert {:error, _} = Auth.reporting_token(options(directory))
    end
  end

  test "failed refresh never downgrades this or subsequent reports", %{tmp_dir: directory} do
    path = Path.join([directory, "tuist", "credentials", "tuist.example.json"])
    File.mkdir_p!(Path.dirname(path))
    contents = JSON.encode!(%{"accessToken" => "expired", "refreshToken" => "revoked"})
    File.write!(path, contents)

    expect(HTTP, :request, 2, fn :post, url, _body ->
      assert String.ends_with?(url, "/api/auth/refresh_token")
      {:ok, 401, %{}}
    end)

    assert {:error, _} = Auth.reporting_token(options(directory))
    assert File.read!(path) == contents
    assert {:error, _} = Auth.reporting_token(options(directory))
  end

  test "hosted aliases and default destinations refuse credential-free publishing", %{
    tmp_dir: directory
  } do
    reject(HTTP, :request, 4)

    for url <- [
          "https://tuist.dev",
          "https://cloud.tuist.io",
          "https://CLOUD.TUIST.IO.",
          "https://canary.tuist.dev",
          "https://tuist.io"
        ] do
      assert {:error, message} = Auth.reporting_token(options(directory, %{"TUIST_URL" => url}))
      assert message =~ "self-hosted"
    end
  end

  test "supplied CI identity is exchanged and never silently ignored", %{tmp_dir: directory} do
    opts = options(directory, %{"CIRCLECI" => "true", "CIRCLE_OIDC_TOKEN_V2" => "identity"})

    expect(HTTP, :request, fn :post, url, body ->
      assert String.ends_with?(url, "/api/auth/oidc/token")
      assert body == %{token: "identity"}
      {:ok, 200, %{"access_token" => "exchanged-access"}}
    end)

    assert {:ok, "exchanged-access"} = Auth.reporting_token(opts)
  end

  test "rejected or malformed supplied CI identity fails closed on repeated reports", %{
    tmp_dir: directory
  } do
    opts = options(directory, %{"CIRCLECI" => "true", "CIRCLE_OIDC_TOKEN_V2" => "rejected"})

    expect(HTTP, :request, 2, fn :post, url, _body ->
      assert String.ends_with?(url, "/api/auth/oidc/token")
      {:ok, 401, %{}}
    end)

    reject(HTTP, :request, 4)
    assert {:error, _} = Auth.reporting_token(opts)
    assert {:error, _} = Auth.reporting_token(opts)

    assert {:error, _} =
             Auth.reporting_token(options(directory, %{"ACTIONS_ID_TOKEN_REQUEST_TOKEN" => ""}))
  end

  test "network reporting retries supplied GitHub identity and propagates the sleep option", %{
    tmp_dir: directory
  } do
    opts =
      options(directory, %{
        "GITHUB_ACTIONS" => "true",
        "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://actions.example/token",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "identity-secret"
      })
      |> Keyword.put(:sleep, fn delay -> send(self(), {:slept, delay}) end)

    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    expect(HTTP, :request, 2, fn :get,
                                 "https://actions.example/token?audience=tuist",
                                 nil,
                                 headers ->
      assert headers == [{"authorization", "Bearer identity-secret"}]

      case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
        0 -> {:ok, 503, %{}}
        1 -> {:ok, 200, %{"value" => "identity"}}
      end
    end)

    expect(HTTP, :request, fn :post, url, body ->
      assert String.ends_with?(url, "/api/auth/oidc/token")
      assert body == %{token: "identity"}
      {:ok, 200, %{"access_token" => "exchanged-access"}}
    end)

    assert {:ok, "exchanged-access"} = Auth.reporting_token(opts)
    assert_received {:slept, 1_000}
  end

  test "exhausted GitHub identity retries never downgrade to an unsigned report", %{
    tmp_dir: directory
  } do
    opts =
      options(directory, %{
        "GITHUB_ACTIONS" => "true",
        "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://actions.example/token",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "identity-secret"
      })
      |> Keyword.put(:sleep, fn _ -> :ok end)

    expect(HTTP, :request, 5, fn :get, _, nil, headers ->
      assert headers == [{"authorization", "Bearer identity-secret"}]
      {:ok, 503, %{}}
    end)

    reject(HTTP, :request, 3)
    assert {:error, message} = Auth.reporting_token(opts)
    assert message =~ "GitHub Actions identity token request"
  end

  test "explicit opt-out keeps ordinary authentication", %{tmp_dir: directory} do
    expect(Auth, :token, fn _ -> {:error, "authentication required"} end)

    assert {:error, "authentication required"} =
             Auth.reporting_token(
               options(directory, %{"TUIST_NETWORK_TRUSTED_PUBLISHING" => "false"})
             )
  end
end
