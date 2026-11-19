defmodule Atlas.Integrations.GitHubAPITest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Integrations.GitHubApp

  setup :verify_on_exit!

  test "personal repository discovery paginates and projects only accessible repository names" do
    expect(Req, :get, 2, fn url, opts ->
      assert url == "https://api.github.com/user/installations/42/repositories"
      assert opts[:auth] == {:bearer, "personal-grant"}
      assert opts[:redirect] == false and opts[:retry] == false
      page = opts[:params][:page]

      entries =
        if page == 1,
          do: Enum.map(1..100, &%{"full_name" => "Acme/Repo#{&1}", "secret" => "not returned"}),
          else: [%{"full_name" => "Acme/Last"}]

      {:ok, %Req.Response{status: 200, body: %{"total_count" => 101, "repositories" => entries}}}
    end)

    assert {:ok, repositories} = GitHubAPI.accessible_repositories("personal-grant", "42")
    assert length(repositories) == 101
    assert %{full_name: "acme/last"} in repositories
    assert Enum.all?(repositories, &(Map.keys(&1) == [:full_name]))
  end

  test "discovery fails closed on upstream errors, malformed pages and oversized catalogues" do
    for {response, error} <- [
          {%Req.Response{status: 401, body: "credential-bearing upstream body"}, :github_connection_required},
          {%Req.Response{status: 302, body: "private destination"}, :github_catalog_unavailable},
          {%Req.Response{status: 200, body: %{"total_count" => 5001, "repositories" => []}}, :github_catalog_limit},
          {%Req.Response{status: 200, body: %{"total_count" => 101, "repositories" => []}}, :github_catalog_unavailable}
        ] do
      stub(Req, :get, fn _, _ -> {:ok, response} end)
      assert {:error, ^error} = GitHubAPI.accessible_repositories("personal-grant", "42")
    end

    assert {:error, :invalid_params} = GitHubAPI.accessible_repositories("personal-grant", "../app/installations")
  end

  test "installation discovery omits suspended installations and unrelated metadata" do
    expect(Req, :get, fn url, _ ->
      assert url == "https://api.github.com/user/installations"

      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "total_count" => 2,
           "installations" => [
             %{"id" => 42, "account" => %{"login" => "Acme"}, "access_tokens_url" => "not returned"},
             %{"id" => 99, "account" => %{"login" => "Suspended"}, "suspended_at" => "2026-10-29"}
           ]
         }
       }}
    end)

    assert {:ok, [%{id: "42", name: "Acme"}]} = GitHubAPI.accessible_installations("personal-grant")
  end

  describe "find_installation_id/2" do
    test "requests app installations with a GitHub App JWT and returns the matching account installation" do
      app = github_app()
      test_pid = self()

      Req
      |> expect(:get, fn url, opts ->
        assert url == "https://api.github.com/app/installations"
        assert opts[:headers] |> List.keyfind("accept", 0) == {"accept", "application/vnd.github+json"}

        assert {"authorization", "Bearer " <> jwt} =
                 List.keyfind(opts[:headers], "authorization", 0)

        send(test_pid, {:jwt, jwt})

        {:ok,
         %Req.Response{
           status: 200,
           body: [
             %{"id" => 123, "account" => %{"login" => "other"}},
             %{"id" => 456, "account" => %{"login" => "tuist"}}
           ]
         }}
      end)

      assert {:ok, "456"} = GitHubAPI.find_installation_id(app, "tuist")
      assert_receive {:jwt, jwt}
      assert_github_app_jwt(jwt, app.app_id)
    end

    test "returns an error when GitHub returns a non-200 response" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"message" => "server error"}}}
      end)

      assert {:error, message} = GitHubAPI.find_installation_id(github_app(), "tuist")
      assert message =~ "GitHub installations request returned 500"
    end

    test "returns request errors" do
      Req
      |> expect(:get, fn _url, _opts -> {:error, :timeout} end)

      assert {:error, :timeout} = GitHubAPI.find_installation_id(github_app(), "tuist")
    end

    test "returns an error when the app is not installed on the account" do
      Req
      |> expect(:get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           body: [%{"id" => 123, "account" => %{"login" => "other"}}]
         }}
      end)

      assert {:error, :github_app_installation_not_found} =
               GitHubAPI.find_installation_id(github_app(), "tuist")
    end
  end

  defp github_app do
    %GitHubApp{
      app_id: "3700470",
      private_key: private_key_pem()
    }
  end

  defp private_key_pem do
    key = :public_key.generate_key({:rsa, 2048, 65_537})

    :public_key.pem_entry_encode(:RSAPrivateKey, key)
    |> List.wrap()
    |> :public_key.pem_encode()
  end

  defp assert_github_app_jwt(jwt, app_id) do
    [header, payload, signature] = String.split(jwt, ".")

    assert %{"alg" => "RS256", "typ" => "JWT"} = decode_jwt_part(header)
    assert %{"iss" => ^app_id, "iat" => iat, "exp" => exp} = decode_jwt_part(payload)
    assert is_integer(iat)
    assert is_integer(exp)
    assert exp > iat
    assert byte_size(Base.url_decode64!(signature, padding: false)) > 0
  end

  defp decode_jwt_part(part) do
    part
    |> Base.url_decode64!(padding: false)
    |> Jason.decode!()
  end
end
