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
          "TUIST_ACTOR_ID" => "developer-123",
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

  test "real formatter payloads use the common unsigned contract and tolerate evolving responses",
       %{tmp_dir: directory} do
    opts = options(directory, %{"TUIST_TAGS" => "compatibility"})

    {:ok, state} =
      TuistEx.Analytics.ExUnitFormatter.init(
        opts ++ [submit: fn _, _ -> :ok end, mode: {:defer, self()}]
      )

    {:noreply, _} =
      TuistEx.Analytics.ExUnitFormatter.handle_cast({:suite_finished, %{run: 1_000}}, state)

    assert_receive {:deferred_test_run, {payload, _, false}}
    runtime_fields = ~w(contract_version elixir_version otp_version mix_env custom_metadata)
    assert Enum.all?(runtime_fields, &Map.has_key?(payload, String.to_existing_atom(&1)))

    for response <- [
          %{"id" => "old-server"},
          %{"id" => "new-server", "actor" => nil},
          %{
            "id" => "future-server",
            "actor" => %{"source" => "future", "submission_auth" => "future"},
            "future" => %{}
          }
        ],
        body <- [payload, JSON.decode!(JSON.encode!(payload))] do
      expect(HTTP, :request, fn :post, _url, body, headers ->
        wire = JSON.decode!(JSON.encode!(body))
        refute Enum.any?(runtime_fields, &Map.has_key?(wire, &1))
        refute Map.has_key?(wire, "git_remote_url_origin")
        assert wire["build_system"] == "mix"
        refute Enum.any?(headers, fn {name, _} -> name == "authorization" end)
        {:ok, 200, response}
      end)

      assert {:ok, ^response} = AnalyticsHTTP.project_request(:post, "/tests", body, opts)
    end
  end

  test "signed tests and unsigned Mix builds retain their existing runtime metadata", %{
    tmp_dir: directory
  } do
    payload = %{
      contract_version: "future",
      elixir_version: "1.20",
      custom_metadata: %{tags: ["compatibility"]}
    }

    for {suffix, overrides} <- [
          {"/tests", %{"TUIST_TOKEN" => "existing-token"}},
          {"/mix/builds", %{}}
        ] do
      expect(HTTP, :request, fn :post, _url, body, _headers ->
        assert body == payload
        {:ok, 201, %{"actor" => %{"source" => "future"}}}
      end)

      assert :ok =
               if(suffix == "/tests",
                 do: AnalyticsHTTP.submit_test_run(payload, options(directory, overrides)),
                 else: AnalyticsHTTP.submit_mix_build(payload, options(directory, overrides))
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

  test "an existing uninspectable credentials directory fails closed", %{tmp_dir: directory} do
    File.mkdir_p!(Path.join(directory, "tuist"))
    File.write!(Path.join([directory, "tuist", "credentials"]), "not a directory")
    reject(HTTP, :request, 4)
    assert {:error, _} = Auth.reporting_token(options(directory))
    assert {:error, _} = Auth.token(options(directory))
    assert {:error, _} = AnalyticsHTTP.submit_mix_build(%{}, options(directory))
  end

  test "umbrella reporting and credential lookup use the same root project configuration", %{
    tmp_dir: directory
  } do
    opts =
      options(directory, %{"TUIST_URL" => nil}) ++
        [
          project_config: [
            url: "https://tuist.umbrella.example",
            project: "acme/widgets",
            network_trusted_publishing: true
          ]
        ]

    assert {:ok, nil} = Auth.reporting_token(opts)
    path = Path.join([directory, "tuist", "credentials", "tuist.umbrella.example.json"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(%{"accessToken" => "rejected", "rejected" => true}))
    assert {:error, _} = Auth.reporting_token(opts)
    assert {:error, _} = Auth.token(opts)
    reject(HTTP, :request, 4)
    assert {:error, _} = AnalyticsHTTP.submit_mix_build(%{}, opts)
  end

  test "hostname aliases cannot hide rejected or corrupt credentials", %{tmp_dir: directory} do
    credentials = Path.join([directory, "tuist", "credentials"])
    File.mkdir_p!(credentials)

    for filename <- ["tuist.example.json", "Tuist.Example..json"] do
      path = Path.join(credentials, filename)

      for contents <- [
            "not-json",
            JSON.encode!(%{"accessToken" => "rejected", "rejected" => true})
          ] do
        File.write!(path, contents)

        for url <- ["https://tuist.example", "https://TUIST.EXAMPLE."] do
          assert {:error, _} = Auth.reporting_token(options(directory, %{"TUIST_URL" => url}))
          assert {:error, _} = Auth.reporting_token(options(directory, %{"TUIST_URL" => url}))
          assert File.read!(path) == contents
        end
      end

      File.rm!(path)
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

  test "ordinary authenticated OIDC fallback survives directory errors without enabling unsigned reporting",
       %{tmp_dir: directory} do
    File.mkdir_p!(Path.join(directory, "tuist"))
    File.write!(Path.join([directory, "tuist", "credentials"]), "not a directory")

    opts =
      options(directory, %{
        "GITHUB_ACTIONS" => "true",
        "ACTIONS_ID_TOKEN_REQUEST_URL" => "https://actions.example/token",
        "ACTIONS_ID_TOKEN_REQUEST_TOKEN" => "identity-secret"
      })

    assert {:error, _} = Auth.reporting_token(opts)

    expect(HTTP, :request, fn :get,
                              "https://actions.example/token?audience=tuist",
                              nil,
                              _headers ->
      {:ok, 200, %{"value" => "identity"}}
    end)

    expect(HTTP, :request, fn :post, _url, %{token: "identity"} ->
      {:ok, 200, %{"access_token" => "exchanged-access"}}
    end)

    assert {:ok, "exchanged-access"} = Auth.token(opts)
    assert {:error, _} = Auth.reporting_token(opts)
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
