defmodule TuistEx.Analytics.NetworkTrustedPublishingTest do
  use ExUnit.Case, async: true
  use Mimic

  alias TuistEx.Analytics.ExUnitFormatter
  alias TuistEx.Analytics.HTTP, as: AnalyticsHTTP
  alias TuistEx.Auth
  alias TuistEx.HTTP

  @moduletag :tmp_dir

  setup do
    stub(HTTP, :request, fn :get, url, nil ->
      assert String.ends_with?(url, "/.well-known/tuist.json")
      {:ok, 200, %{"network_trusted_report_publishing" => true}}
    end)

    :ok
  end

  defp options(directory, overrides \\ %{}) do
    values =
      Map.merge(
        %{
          "TUIST_URL" => "https://tuist.example",
          "TUIST_PROJECT" => "acme/widgets",
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
      ExUnitFormatter.init(opts ++ [submit: fn _, _ -> :ok end, mode: {:defer, self()}])

    {:noreply, _} =
      ExUnitFormatter.handle_cast({:suite_finished, %{run: 1_000}}, state)

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

  test "supplied credentials retain authenticated publishing without discovery", %{
    tmp_dir: directory
  } do
    reject(HTTP, :request, 3)

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
    reject(HTTP, :request, 3)
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
      assert message =~ "mix tuist.login"
    end
  end

  test "hosted CI keeps ordinary token caching and skips network-mode discovery", %{
    tmp_dir: directory
  } do
    opts =
      options(directory, %{
        "TUIST_URL" => "https://tuist.dev",
        "CIRCLE_OIDC_TOKEN_V2" => "identity"
      })

    reject(HTTP, :request, 3)
    expect(Auth, :token, fn ^opts -> {:ok, "cached-ci-token"} end)
    refute Auth.network_publishing?(opts)
    assert {:ok, "cached-ci-token"} = Auth.reporting_token(opts)
  end

  test "invalid analytics URLs cannot raise from mode detection", %{tmp_dir: directory} do
    for url <- ["not-a-url", "https://user:secret@tuist.example", "https://tuist.example?query"] do
      opts = options(directory, %{"TUIST_URL" => url})
      refute Auth.network_publishing?(opts)
      assert {:error, _} = Auth.reporting_token(opts)
    end
  end

  test "mode probes never refresh credentials or exchange supplied identities", %{
    tmp_dir: directory
  } do
    reject(HTTP, :request, 3)
    reject(HTTP, :request, 4)
    reject(Auth, :reporting_token, 1)
    opts = options(directory, %{"XDG_STATE_HOME" => Path.join(directory, "state")})

    for value <- ["", " ", "supplied"] do
      refute Auth.network_publishing?(options(directory, %{"TUIST_TOKEN" => value}))
    end

    for variable <-
          ~w(TUIST_OIDC_TOKEN ACTIONS_ID_TOKEN_REQUEST_TOKEN CIRCLE_OIDC_TOKEN_V2 BITRISE_OIDC_ID_TOKEN),
        value <- ["", "identity"] do
      refute Auth.network_publishing?(options(directory, %{variable => value}))
    end

    path = Path.join([directory, "tuist", "credentials", "tuist.example.json"])
    File.mkdir_p!(Path.dirname(path))

    for contents <- [
          "corrupt",
          JSON.encode!(%{"accessToken" => "expired", "refreshToken" => "rotating-refresh"})
        ] do
      File.write!(path, contents)
      refute Auth.network_publishing?(opts)
      assert File.read!(path) == contents
    end

    refute File.exists?(Path.join(directory, "state"))
  end

  test "dangling credential files and directories never permit unsigned publication", %{
    tmp_dir: directory
  } do
    for relative <- ["tuist", "tuist/credentials", "tuist/credentials/tuist.example.json"] do
      home = Path.join(directory, String.replace(relative, "/", "-"))
      link = Path.join(home, relative)
      File.mkdir_p!(Path.dirname(link))
      File.ln_s!(Path.join(home, "missing"), link)
      opts = options(home)
      refute Auth.network_publishing?(opts)
      assert {:error, _} = Auth.reporting_token(opts)
      assert {:ok, _} = File.read_link(link)
    end
  end

  test "an inconclusive probe still strips privileged data if submission discovers unsigned mode",
       %{tmp_dir: directory} do
    opts = options(directory)
    expect(HTTP, :request, fn :get, _, nil -> {:error, :timeout} end)
    refute Auth.network_publishing?(opts)

    expect(HTTP, :request, fn :get, _, nil ->
      {:ok, 200, %{"network_trusted_report_publishing" => true}}
    end)

    expect(HTTP, :request, fn :post, _, body, headers ->
      refute Enum.any?(headers, fn {key, _} -> key == "authorization" end)
      refute Map.has_key?(body, :git_history)
      refute Map.has_key?(body, :coverage)
      refute Map.has_key?(body, :git_remote_url_origin)
      {:ok, 200, %{"id" => "unsigned"}}
    end)

    assert {:ok, _} =
             AnalyticsHTTP.project_request(
               :post,
               "/tests",
               %{git_history: %{}, coverage: %{}, git_remote_url_origin: "private-origin"},
               opts
             )
  end

  test "self-hosted CI reuses its exchanged token across reports", %{
    tmp_dir: directory
  } do
    url = "https://oidc-#{System.unique_integer([:positive])}.example"
    key = {Auth, :provider_token, url, nil}
    on_exit(fn -> :persistent_term.erase(key) end)

    payload =
      %{exp: System.system_time(:second) + 3_600}
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    token = "header.#{payload}.signature"

    opts =
      options(directory, %{
        "TUIST_URL" => url,
        "CIRCLECI" => "true",
        "CIRCLE_OIDC_TOKEN_V2" => "identity"
      })

    expect(HTTP, :request, fn :post, exchange_url, %{token: "identity"} ->
      assert exchange_url == url <> "/api/auth/oidc/token"
      {:ok, 200, %{"access_token" => token}}
    end)

    assert {:ok, ^token} = Auth.reporting_token(opts)
    refute Auth.network_publishing?(opts)
    assert {:ok, ^token} = Auth.reporting_token(opts)
    refute File.exists?(Path.join([directory, "tuist", "credentials"]))
  end

  test "self-hosted workload reporting binds cached sessions to the supplied identity and account",
       %{
         tmp_dir: directory
       } do
    url = "https://workload-#{System.unique_integer([:positive])}.example"

    for account <- ["acme", "other"] do
      on_exit(fn -> :persistent_term.erase({Auth, :provider_token, url, account}) end)
    end

    for {account, identity} <- [{"acme", "first"}, {"acme", "second"}, {"other", "second"}] do
      payload =
        %{exp: System.system_time(:second) + 3_600, account: account, identity: identity}
        |> JSON.encode!()
        |> Base.url_encode64(padding: false)

      token = "header.#{payload}.signature"

      opts =
        options(directory, %{
          "TUIST_URL" => url,
          "TUIST_OIDC_ACCOUNT" => " #{account} ",
          "TUIST_OIDC_TOKEN" => " #{identity}\n"
        })

      expect(HTTP, :request, fn :post,
                                exchange_url,
                                %{token: ^identity, account_handle: ^account} ->
        assert exchange_url == url <> "/api/auth/oidc/token"
        {:ok, 200, %{"access_token" => token}}
      end)

      refute Auth.network_publishing?(opts)
      assert {:ok, ^token} = Auth.reporting_token(opts)
      assert {:ok, ^token} = Auth.reporting_token(opts)
    end

    reject(HTTP, :request, 3)

    for identity <- ["", " \n "] do
      opts =
        options(directory, %{
          "TUIST_URL" => url,
          "TUIST_OIDC_ACCOUNT" => "acme",
          "TUIST_OIDC_TOKEN" => identity
        })

      refute Auth.network_publishing?(opts)
      assert {:error, message} = Auth.reporting_token(opts)
      assert message =~ "TUIST_OIDC_TOKEN is empty"
    end
  end

  test "self-hosted empty environment and stale stored tokens retain authenticated fallback", %{
    tmp_dir: directory
  } do
    stub(HTTP, :request, fn method, url, _ -> flunk("Unexpected #{method} request to #{url}") end)

    payload =
      %{exp: System.system_time(:second) + 3_600}
      |> JSON.encode!()
      |> Base.url_encode64(padding: false)

    token = "header.#{payload}.signature"

    for mode <- [:empty_with_stored, :empty_with_oidc, :expired_with_oidc] do
      host = "#{mode}-#{System.unique_integer([:positive])}.example"
      url = "https://#{host}"
      on_exit(fn -> :persistent_term.erase({Auth, :provider_token, url, nil}) end)
      values = %{"TUIST_URL" => url, "XDG_STATE_HOME" => Path.join(directory, "state")}
      values = if mode == :expired_with_oidc, do: values, else: Map.put(values, "TUIST_TOKEN", "")

      values =
        if mode == :empty_with_stored,
          do: values,
          else: Map.merge(values, %{"CIRCLECI" => "true", "CIRCLE_OIDC_TOKEN_V2" => "identity"})

      opts = options(directory, values)
      path = Path.join([directory, "tuist", "credentials", "#{host}.json"])

      if mode != :empty_with_oidc do
        File.mkdir_p!(Path.dirname(path))
        access = if mode == :empty_with_stored, do: token, else: "expired"
        File.write!(path, JSON.encode!(%{"accessToken" => access}))
      end

      if mode != :empty_with_stored do
        expect(HTTP, :request, fn :post, exchange_url, %{token: "identity"} ->
          assert exchange_url == url <> "/api/auth/oidc/token"
          {:ok, 200, %{"access_token" => token}}
        end)
      end

      refute Auth.network_publishing?(opts)
      assert {:ok, ^token} = Auth.reporting_token(opts)

      expect(HTTP, :request, fn :post, report_url, body, headers ->
        assert report_url == url <> "/api/projects/acme/widgets/tests"
        assert {"authorization", "Bearer " <> token} in headers
        assert body.git_remote_url_origin == "private-origin"
        {:ok, 200, %{"id" => "signed-report"}}
      end)

      assert :ok = AnalyticsHTTP.submit_test_run(%{git_remote_url_origin: "private-origin"}, opts)
    end
  end

  test "failed authenticated fallbacks never discover or publish anonymously", %{
    tmp_dir: directory
  } do
    stub(HTTP, :request, fn :get, url, _ -> flunk("Must not discover #{url}") end)

    for mode <- [:empty, :expired] do
      host = "failed-#{mode}-#{System.unique_integer([:positive])}.example"

      values = %{
        "TUIST_URL" => "https://#{host}",
        "CIRCLECI" => "true",
        "CIRCLE_OIDC_TOKEN_V2" => "rejected",
        "XDG_STATE_HOME" => Path.join(directory, "state")
      }

      values = if mode == :empty, do: Map.put(values, "TUIST_TOKEN", ""), else: values

      if mode == :expired do
        path = Path.join([directory, "tuist", "credentials", "#{host}.json"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, JSON.encode!(%{"accessToken" => "expired"}))
      end

      expect(HTTP, :request, 2, fn :post, url, %{token: "rejected"} ->
        assert String.ends_with?(url, "/api/auth/oidc/token")
        {:ok, 401, %{}}
      end)

      opts = options(directory, values)

      for _ <- 1..2 do
        refute Auth.network_publishing?(opts)
        assert {:error, _} = Auth.reporting_token(opts)
      end
    end
  end

  test "hosted empty tokens and corrupt stored credentials retain authenticated OIDC fallback", %{
    tmp_dir: directory
  } do
    for {host, contents} <- [{"empty-token.tuist.dev", nil}, {"stale-token.tuist.dev", "corrupt"}] do
      url = "https://#{host}"
      key = {Auth, :provider_token, url, nil}
      on_exit(fn -> :persistent_term.erase(key) end)

      if contents do
        path = Path.join([directory, "tuist", "credentials", "#{host}.json"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, contents)
      end

      opts =
        options(directory, %{
          "TUIST_URL" => url,
          "TUIST_TOKEN" => "",
          "CIRCLECI" => "true",
          "CIRCLE_OIDC_TOKEN_V2" => "identity"
        })

      expect(HTTP, :request, fn :post, exchange_url, %{token: "identity"} ->
        assert exchange_url == url <> "/api/auth/oidc/token"
        {:ok, 200, %{"access_token" => "authenticated-access"}}
      end)

      assert {:ok, "authenticated-access"} = Auth.reporting_token(opts)
      refute Auth.network_publishing?(opts)
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

  test "supplied workload identity authenticates to the selected account instead of publishing anonymously",
       %{
         tmp_dir: directory
       } do
    opts =
      options(directory, %{
        "TUIST_OIDC_TOKEN" => " fly-identity \n",
        "TUIST_OIDC_ACCOUNT" => " acme \n"
      })

    expect(HTTP, :request, fn :post, url, body ->
      assert String.ends_with?(url, "/api/auth/oidc/token")
      assert body == %{token: "fly-identity", account_handle: "acme"}
      {:ok, 200, %{"access_token" => "exchanged-access"}}
    end)

    assert {:ok, "exchanged-access"} = Auth.reporting_token(opts)
  end

  test "rejected and blank workload identities never downgrade to anonymous publishing", %{
    tmp_dir: directory
  } do
    opts = options(directory, %{"TUIST_OIDC_TOKEN" => "rejected"})

    expect(HTTP, :request, 2, fn :post, url, body ->
      assert String.ends_with?(url, "/api/auth/oidc/token")
      assert body == %{token: "rejected"}
      {:ok, 401, %{}}
    end)

    assert {:error, _} = Auth.reporting_token(opts)
    assert {:error, _} = Auth.reporting_token(opts)

    reject(HTTP, :request, 3)

    for token <- ["", " \n "] do
      assert {:error, message} =
               Auth.reporting_token(options(directory, %{"TUIST_OIDC_TOKEN" => token}))

      assert message =~ "TUIST_OIDC_TOKEN is empty"
    end
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

  test "future discovery metadata does not change the explicit publishing capability", %{
    tmp_dir: directory
  } do
    expect(HTTP, :request, fn :get, _, nil ->
      {:ok, 200,
       %{
         "network_trusted_report_publishing" => true,
         "future" => %{"version" => 2, "capabilities" => ["unknown"]}
       }}
    end)

    assert {:ok, nil} = Auth.reporting_token(options(directory))
  end

  test "disabled, old, malformed and unavailable servers do not permit unsigned reports", %{
    tmp_dir: directory
  } do
    for response <- [
          {:ok, 200, %{"network_trusted_report_publishing" => false}},
          {:ok, 200, %{"network_trusted_report_publishing" => "true"}},
          {:ok, 200, %{"network_trusted_report_publishing" => nil}},
          {:ok, 200, %{"network_trusted_report_publishing" => %{"enabled" => true}}},
          {:ok, 200, []},
          {:ok, 200, %{}},
          {:ok, 404, %{}},
          {:ok, 302, %{}},
          {:ok, 503, %{}},
          {:error, :timeout}
        ] do
      expect(HTTP, :request, fn :get, "https://tuist.example/.well-known/tuist.json", nil ->
        response
      end)

      reject(HTTP, :request, 4)
      assert {:error, message} = Auth.reporting_token(options(directory))
      assert message =~ "requires authentication"
    end
  end
end
