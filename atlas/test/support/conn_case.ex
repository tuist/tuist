defmodule AtlasWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use AtlasWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Atlas.Authorization
  alias Atlas.Authorization.Roles
  alias Atlas.Authorization.UserRole
  alias Atlas.OAuth.AccessTokens
  alias Atlas.OAuth.Clients
  alias Atlas.Users.User

  using do
    quote do
      use AtlasWeb, :verified_routes

      import AtlasWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn
      # The default endpoint for testing
      @endpoint AtlasWeb.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup tags do
    Atlas.DataCase.setup_sandbox(tags)

    # Lifecycle tests opt in and await cleanup while their sandbox is still owned.
    # Unrelated LiveViews must not start cleanup tasks that outlive that sandbox.
    if !tags[:presence_tracking] do
      Mimic.stub(Atlas.Presence, :track, fn _user, _connection_id -> {:ok, self()} end)
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Inserts a user (with a `tuist.dev` email and `employee` role by default) and
  stores their id in the test session, mimicking a successful Google sign-in.

  The default email is unique per call. `users.email` is unique across the
  table, so a shared default would make every concurrent test that logs in
  queue behind whichever one inserted it first, and deadlock outright once two
  of them also contend on a second shared key.
  """
  def log_in_user(conn, attrs \\ %{}) do
    defaults = %{
      email: "test-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Test User"
    }

    {role, scopes, attrs} = extract_role_and_scopes(attrs)

    {:ok, user} =
      %User{}
      |> User.changeset(Map.merge(defaults, attrs))
      |> Atlas.Repo.insert()

    assign_role_or_scopes(user, role, scopes)

    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  @doc "Creates a persisted OAuth access token, including its client, for API/MCP tests."
  def oauth_access_token_fixture(%User{} = user) do
    {:ok, client} =
      Clients.create_client(%{"name" => "Test OAuth client", "redirect_uris" => ["https://example.com/callback"]})

    {:ok, token} = AccessTokens.create(%{client: client, scope: "mcp", sub: user.id}, refresh_token: true)
    token.value
  end

  @doc false
  def extract_role_and_scopes(attrs) do
    {role, attrs} = Map.pop(attrs, :role)
    {scopes, attrs} = Map.pop(attrs, :scopes)
    {role, scopes, attrs}
  end

  @doc false
  def assign_role_or_scopes(_user, nil, nil), do: :ok
  def assign_role_or_scopes(_user, :employee, nil), do: :ok

  def assign_role_or_scopes(user, :executive, _scopes) do
    role = Roles.ensure_executive_role!()
    %UserRole{} |> UserRole.changeset(%{user_id: user.id, role_id: role.id}) |> Atlas.Repo.insert!()
    :ok
  end

  def assign_role_or_scopes(user, _role, scopes) when is_list(scopes) do
    scope_strings = scopes |> Enum.map(&to_string/1) |> Authorization.expand()

    {:ok, ad_hoc} =
      Roles.create_role(%{
        name: "Test scopes #{user.email}",
        slug: "test-#{user.id}",
        scopes: scope_strings
      })

    %UserRole{}
    |> UserRole.changeset(%{user_id: user.id, role_id: ad_hoc.id})
    |> Atlas.Repo.insert!()

    :ok
  end
end
