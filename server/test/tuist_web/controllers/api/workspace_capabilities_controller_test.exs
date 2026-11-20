defmodule TuistWeb.API.WorkspaceCapabilitiesControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.FeatureFlags
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Repo
  alias Tuist.Sandboxes.Sandbox
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures
  alias TuistWeb.API.WorkspaceCapabilitiesController
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, client} = Clients.create_client(%{redirect_uris: ["https://luft.invalid/callback"], name: "capability"})
    stub(Clients, :luft_server_client_id, fn -> client.id end)
    stub(FeatureFlags, :luft_enabled?, fn _ -> true end)
    stub(FeatureFlags, :sandboxes_enabled?, fn _ -> true end)
    stub(FeatureFlags, :organization_luft_enabled?, fn _ -> true end)
    stub(Authentication, :oauth_user, fn _ -> user end)
    sandbox = Repo.insert!(%Sandbox{account_id: user.account.id, state: :running})
    %{user: user, client: client, sandbox: sandbox}
  end

  test "only a configured scoped Luft grant can use capabilities", c do
    body = %{"operation" => "show", "sandbox_id" => c.sandbox.id}

    assert %{"result" => %{"id" => id}} =
             c |> request(oauth(c, "luft:app account:sandboxes:write"), body) |> json_response(200)

    assert id == c.sandbox.id
    assert request(c, oauth(c, "luft:app"), body).status == 404
    assert request(c, oauth(c, "account:sandboxes:write"), body).status == 404
    bearer = oauth(c, "luft:app account:sandboxes:write")
    Token |> Repo.get_by!(value: bearer) |> Ecto.Changeset.change(revoked_at: DateTime.utc_now()) |> Repo.update!()
    assert request(c, bearer, body).status == 404
    {:ok, foreign} = Clients.create_client(%{redirect_uris: ["https://foreign.invalid/callback"], name: "foreign"})
    assert request(c, oauth(%{c | client: foreign}, "luft:app account:sandboxes:write"), body).status == 404
  end

  test "fresh account membership and active user state override stale authentication", c do
    bearer = oauth(c, "luft:app account:sandboxes:write")
    stranger = AccountsFixtures.user_fixture(preload: [:account])
    foreign = Repo.insert!(%Sandbox{account_id: stranger.account.id, state: :running})
    assert request(c, bearer, %{"operation" => "show", "sandbox_id" => foreign.id}).status == 409
    Repo.update!(Ecto.Changeset.change(c.user, active: false))
    assert request(c, bearer, %{"operation" => "show", "sandbox_id" => c.sandbox.id}).status == 404
  end

  test "repository listing is exposed only to the repository-read grant", c do
    VCSFixtures.github_app_installation_fixture(account: c.user)

    stub(Tuist.GitHub.Client, :list_installation_repositories, fn _, _ ->
      {:ok,
       %{
         meta: %{next_url: nil},
         repositories: [%{full_name: "tuist/repository", default_branch: "main", size: 42, secret: "not exposed"}]
       }}
    end)

    assert %{"result" => [%{"full_name" => "tuist/repository", "default_branch" => "main", "size" => 42} = repository]} =
             c
             |> request(oauth(c, "luft:app account:repositories:read"), %{"operation" => "repositories"})
             |> json_response(200)

    refute Map.has_key?(repository, "secret")
    assert request(c, oauth(c, "luft:app account:sandboxes:write"), %{"operation" => "repositories"}).status == 404
  end

  test "residency release is account scoped and compare-and-swap; unknown writes never succeed", c do
    bearer = oauth(c, "luft:app account:sandboxes:write")
    sandbox = Repo.update!(Ecto.Changeset.change(c.sandbox, residency_work_id: "replacement"))
    assert request(c, bearer, %{"operation" => "release", "sandbox_id" => sandbox.id, "work_id" => "old"}).status == 200
    assert Repo.reload!(sandbox).residency_work_id == "replacement"
    assert request(c, bearer, %{"operation" => "ship", "head_sha" => String.duplicate("a", 40)}).status == 409
    assert request(c, bearer, %{"operation" => "show", "sandbox_id" => sandbox.id, "extra" => true}).status == 409

    assert request(c, bearer, %{"operation" => "exec", "sandbox_id" => sandbox.id, "argv" => [], "timeout_ms" => 0}).status ==
             409

    command = %{"operation" => "command_read", "sandbox_id" => sandbox.id, "command_id" => Ecto.UUID.generate()}
    assert request(c, bearer, Map.put(command, "stdout_offset", 9_223_372_036_854_775_808)).status == 409
    assert request(c, bearer, Map.put(command, "extra", "not admitted")).status == 409
  end

  defp request(c, bearer, body) do
    conn = put_req_header(build_conn(), "authorization", "Bearer #{bearer}")
    conn = %{conn | body_params: body}
    WorkspaceCapabilitiesController.call_capability(conn, %{"account_handle" => c.user.account.name})
  end

  defp oauth(c, scope) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(c.user.id), client_id: c.client.id})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: c.client.id,
      sub: to_string(c.user.id),
      scope: scope
    })

    bearer
  end
end
