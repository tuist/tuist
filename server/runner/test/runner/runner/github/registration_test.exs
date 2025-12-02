defmodule Runner.Runner.GitHub.RegistrationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Runner.Runner.GitHub.Registration

  # Helper to build a valid JIT config response like GitHub returns
  defp build_jit_config(opts) do
    server_url = Keyword.get(opts, :server_url, "https://pipelines.actions.githubusercontent.com/abc123")
    server_url_v2 = Keyword.get(opts, :server_url_v2, "https://actions.githubusercontent.com/abc123")
    github_url = Keyword.get(opts, :github_url, "https://github.com/test-org")
    auth_url = Keyword.get(opts, :auth_url, "https://vstoken.actions.githubusercontent.com/abc123/_apis/oauth2/token")
    client_id = Keyword.get(opts, :client_id, "test-client-uuid")
    pool_id = Keyword.get(opts, :pool_id, 1)
    agent_id = Keyword.get(opts, :agent_id, 123)

    # Build .runner settings (base64-encoded JSON)
    runner_settings = %{
      "ServerUrl" => server_url,
      "ServerUrlV2" => server_url_v2,
      "GitHubUrl" => github_url,
      "PoolId" => pool_id,
      "AgentId" => agent_id
    }
    runner_b64 = runner_settings |> Jason.encode!() |> Base.encode64()

    # Build .credentials data (base64-encoded JSON with Data field)
    credentials_data = %{
      "Data" => %{
        "AuthorizationUrl" => auth_url,
        "ClientId" => client_id
      }
    }
    credentials_b64 = credentials_data |> Jason.encode!() |> Base.encode64()

    # Build .credentials_rsaparams (base64-encoded JSON with RSA params)
    rsa_params = %{
      "d" => Base.encode64("fake-d-value"),
      "dp" => Base.encode64("fake-dp-value"),
      "dq" => Base.encode64("fake-dq-value"),
      "exponent" => Base.encode64("AQAB"),
      "inverseQ" => Base.encode64("fake-qi-value"),
      "modulus" => Base.encode64("fake-modulus-value"),
      "p" => Base.encode64("fake-p-value"),
      "q" => Base.encode64("fake-q-value")
    }
    rsa_b64 = rsa_params |> Jason.encode!() |> Base.encode64()

    # Build the JIT config (base64-encoded JSON)
    jit_config = %{
      ".runner" => runner_b64,
      ".credentials" => credentials_b64,
      ".credentials_rsaparams" => rsa_b64
    }

    jit_config |> Jason.encode!() |> Base.encode64()
  end

  describe "register/2" do
    test "registers runner with GitHub API for org-level runner" do
      Mimic.stub(Req, :post, fn url, opts ->
        assert String.contains?(url, "/orgs/test-org/actions/runners/generate-jitconfig")
        assert opts[:headers] |> Enum.any?(fn {k, v} -> k == "Authorization" && String.starts_with?(v, "Bearer ") end)

        body = Jason.decode!(opts[:body])
        assert String.starts_with?(body["name"], "test-runner")
        assert body["ephemeral"] == true

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "runner" => %{"id" => 123},
             "encoded_jit_config" => build_jit_config(
               server_url_v2: "https://actions.githubusercontent.com/abc123"
             )
           }
         }}
      end)

      params = %{
        github_org: "test-org",
        github_repo: nil,
        labels: ["self-hosted", "macos"],
        runner_name: "test-runner"
      }

      assert {:ok, result} = Registration.register("test-token", params)
      assert result.runner_id == 123
      assert result.server_url_v2 == "https://actions.githubusercontent.com/abc123"
    end

    test "registers runner with GitHub API for repo-level runner" do
      Mimic.stub(Req, :post, fn url, _opts ->
        assert String.contains?(url, "/repos/test-org/test-repo/actions/runners/generate-jitconfig")

        {:ok,
         %Req.Response{
           status: 200,
           body: %{
             "runner" => %{"id" => 456},
             "encoded_jit_config" => build_jit_config(
               server_url_v2: "https://actions.githubusercontent.com/def456"
             )
           }
         }}
      end)

      params = %{
        github_org: "test-org",
        github_repo: "test-repo",
        labels: ["self-hosted"],
        runner_name: "test-runner"
      }

      assert {:ok, result} = Registration.register("test-token", params)
      assert result.runner_id == 456
    end

    test "returns error on failed registration" do
      Mimic.stub(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"message" => "Unauthorized"}}}
      end)

      params = %{
        github_org: "test-org",
        github_repo: nil,
        labels: ["self-hosted"],
        runner_name: "test-runner"
      }

      assert {:error, {:registration_failed, 401, _}} = Registration.register("invalid-token", params)
    end
  end
end
