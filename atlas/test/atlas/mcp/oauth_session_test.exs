defmodule Atlas.MCP.OAuthSessionTest do
  use Atlas.DataCase, async: true

  alias Atlas.MCP.OAuthSession
  alias Atlas.Repo
  alias Atlas.Users.User

  describe "changeset/2" do
    test "requires user and server name" do
      changeset = OAuthSession.changeset(%OAuthSession{}, %{})

      refute changeset.valid?

      assert %{
               user_id: ["can't be blank"],
               server_name: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "requires status and token type when defaults are cleared" do
      changeset =
        OAuthSession.changeset(
          %OAuthSession{user_id: Atlas.UUIDv7.generate(), server_name: "grafana", status: nil, token_type: nil},
          %{}
        )

      refute changeset.valid?

      assert %{
               status: ["can't be blank"],
               token_type: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "rejects unknown statuses" do
      changeset =
        OAuthSession.changeset(%OAuthSession{user_id: Atlas.UUIDv7.generate(), server_name: "grafana"}, %{
          status: "revoked",
          token_type: "Bearer"
        })

      refute changeset.valid?
      assert %{status: ["is invalid"]} = errors_on(changeset)
    end

    test "does not cast programmatic session ownership fields" do
      user = insert_user!()

      changeset =
        OAuthSession.changeset(%OAuthSession{user_id: user.id, server_name: "grafana"}, %{
          user_id: Atlas.UUIDv7.generate(),
          server_name: "other",
          status: "authorized",
          token_type: "Bearer"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :user_id) == user.id
      assert Ecto.Changeset.get_field(changeset, :server_name) == "grafana"
    end

    test "casts and encrypts token and dynamic client credentials" do
      user = insert_user!()

      {:ok, session} =
        %OAuthSession{user_id: user.id, server_name: "grafana"}
        |> OAuthSession.changeset(%{
          status: "authorized",
          access_token: "access-token",
          refresh_token: "refresh-token",
          client_id: "dynamic-client",
          client_secret: "dynamic-secret",
          token_type: "Bearer",
          scopes: ["grafana:read"],
          expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
          last_refreshed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      assert session.access_token == "access-token"
      assert session.refresh_token == "refresh-token"
      assert session.client_id == "dynamic-client"
      assert session.client_secret == "dynamic-secret"

      persisted = Repo.get!(OAuthSession, session.id)
      assert persisted.access_token == "access-token"
      assert persisted.refresh_token == "refresh-token"
      assert persisted.client_id == "dynamic-client"
      assert persisted.client_secret == "dynamic-secret"
    end

    test "enforces one OAuth session per user and server" do
      user = insert_user!()
      attrs = valid_attrs(user)

      %OAuthSession{user_id: user.id, server_name: "grafana"}
      |> OAuthSession.changeset(attrs)
      |> Repo.insert!()

      assert {:error, changeset} =
               %OAuthSession{user_id: user.id, server_name: "grafana"}
               |> OAuthSession.changeset(attrs)
               |> Repo.insert()

      assert %{user_id: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "valid?/1" do
    test "returns true for authorized sessions that expire outside the refresh window" do
      session = %OAuthSession{
        status: "authorized",
        access_token: "access-token",
        expires_at: DateTime.utc_now() |> DateTime.add(180, :second) |> DateTime.truncate(:second)
      }

      assert OAuthSession.valid?(session)
    end

    test "returns false for sessions inside the refresh window" do
      session = %OAuthSession{
        status: "authorized",
        access_token: "access-token",
        expires_at: DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.truncate(:second)
      }

      refute OAuthSession.valid?(session)
    end

    test "returns false without an authorized status, access token, or expiry" do
      expires_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      refute OAuthSession.valid?(%OAuthSession{
               status: "needs_authorization",
               access_token: "access-token",
               expires_at: expires_at
             })

      refute OAuthSession.valid?(%OAuthSession{status: "authorized", access_token: nil, expires_at: expires_at})
      refute OAuthSession.valid?(%OAuthSession{status: "authorized", access_token: "access-token", expires_at: nil})
    end
  end

  describe "refreshable?/1" do
    test "returns true for authorized sessions with a refresh token" do
      assert OAuthSession.refreshable?(%OAuthSession{
               status: "authorized",
               refresh_token: "refresh-token"
             })
    end

    test "returns false without an authorized status or refresh token" do
      refute OAuthSession.refreshable?(%OAuthSession{
               status: "needs_authorization",
               refresh_token: "refresh-token"
             })

      refute OAuthSession.refreshable?(%OAuthSession{status: "authorized", refresh_token: nil})
      refute OAuthSession.refreshable?(%OAuthSession{status: "authorized", refresh_token: ""})
    end
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{email: "oauth-session-#{System.unique_integer()}@example.com", name: "OAuth Session"})
    |> Repo.insert!()
  end

  defp valid_attrs(%User{}) do
    %{
      status: "authorized",
      token_type: "Bearer"
    }
  end
end
