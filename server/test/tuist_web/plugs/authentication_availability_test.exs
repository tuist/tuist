defmodule TuistWeb.AuthenticationAvailabilityTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Boruta.Oauth.Client
  alias Tuist.Accounts
  alias Tuist.Authentication.TokenVerificationCache
  alias Tuist.Authentication.UnavailableError
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.AuthenticationPlug
  alias TuistWeb.Errors.ServiceUnavailableError

  setup :set_mimic_global

  setup do
    cache = String.to_atom("auth_unavailable_#{UUIDv7.generate()}")
    start_supervised!({TokenVerificationCache, cache: cache})
    %{cache: cache, project: ProjectsFixtures.project_fixture()}
  end

  for kind <- [:project, :account] do
    @kind kind
    test "strict HTTP #{@kind} credentials return 503 rather than 401", %{conn: conn, project: project} do
      token = credential(@kind, project)
      expect(TokenVerificationCache, :verify_pass, 1, fn _, _ -> raise UnavailableError end)

      assert_error_sent 503, fn ->
        conn
        |> assign(:caching, false)
        |> put_req_header("authorization", "Bearer " <> token)
        |> get("/api/cache/access")
      end
    end

    @kind kind
    test "Kura introspection #{@kind} proof failures return 503, never inactive", %{conn: conn, project: project} do
      token = credential(@kind, project)

      client = %Client{
        id: "00000000-0000-0000-0000-000000000001",
        secret: "kura-secret",
        confidential: true,
        supported_grant_types: ["introspect"],
        token_endpoint_auth_methods: ["client_secret_post"]
      }

      stub(Environment, :kura_control_plane_configured?, fn -> true end)
      stub(Environment, :kura_control_plane_client_id, fn -> client.id end)
      stub(Clients, :get_client, fn id -> if id == client.id, do: client end)
      expect(TokenVerificationCache, :verify_pass, 1, fn _, _ -> raise UnavailableError end)

      assert_error_sent 503, fn ->
        post(conn, "/oauth2/introspect", %{
          "client_id" => client.id,
          "client_secret" => client.secret,
          "token" => token
        })
      end
    end

    @kind kind
    test "cached #{@kind} authentication does not retain an unavailable result", %{cache: cache, project: project} do
      token = credential(@kind, project)
      expect(TokenVerificationCache, :verify_pass, 2, fn _, _ -> raise UnavailableError end)

      for _ <- 1..2 do
        conn =
          :get
          |> Plug.Test.conn("/api/cache/access")
          |> assign(:caching, true)
          |> assign(:cache, cache)
          |> assign(:auth_cache_opts, cache: cache)
          |> put_req_header("authorization", "Bearer " <> token)

        assert_raise ServiceUnavailableError, fn ->
          AuthenticationPlug.call(conn, :load_authenticated_subject)
        end
      end

      assert Cachex.size(cache) == 0
    end
  end

  defp credential(:project, project), do: Projects.create_project_token(project)

  defp credential(:account, project) do
    {:ok, {_, token}} =
      Accounts.create_account_token(%{
        account: project.account,
        scopes: ["project:cache:read"],
        name: "unavailable",
        all_projects: true
      })

    token
  end
end
