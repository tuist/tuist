defmodule TuistWeb.SCIM.UsersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.SCIM

  setup %{conn: conn} do
    organization = organization_fixture()
    {:ok, {_token, plaintext}} = SCIM.create_token(organization, %{name: "test"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("content-type", "application/scim+json")

    %{conn: conn, organization: organization, plaintext: plaintext}
  end

  describe "auth" do
    test "401 without bearer" do
      conn = get(build_conn(), "/scim/v2/Users")
      assert json_response(conn, 401)["status"] == "401"
    end

    test "401 with bad bearer" do
      conn = build_conn() |> put_req_header("authorization", "Bearer garbage") |> get("/scim/v2/Users")
      assert json_response(conn, 401)["status"] == "401"
    end
  end

  describe "POST /Users" do
    test "creates a new user and returns a SCIM resource", %{conn: conn} do
      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: "alice@example.com", active: true}))

      body = json_response(conn, 201)
      assert body["userName"] == "alice@example.com"
      assert body["active"] == true
      assert is_binary(body["id"])
      assert hd(get_resp_header(conn, "location")) =~ "/scim/v2/Users/#{body["id"]}"
    end

    for role <- [:user, :admin, :viewer] do
      @role role

      test "preserves an existing #{@role} when roles are omitted", %{conn: conn, organization: org} do
        default_role = if @role == :viewer, do: "user", else: "viewer"
        {:ok, org} = Accounts.update_organization(org, %{sso_default_role: default_role})
        existing = user_fixture()
        :ok = Accounts.add_user_to_organization(existing, org, role: @role)

        conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: existing.email, active: true}))

        assert json_response(conn, 201)["id"] == to_string(existing.id)
        assert %{name: role} = Accounts.get_user_role_in_organization(existing, org)
        assert role == Atom.to_string(@role)
      end
    end

    test "preserves an existing role when no supplied role is recognized", %{conn: conn, organization: org} do
      {:ok, org} = Accounts.update_organization(org, %{sso_default_role: "viewer"})
      existing = user_fixture()
      :ok = Accounts.add_user_to_organization(existing, org, role: :admin)

      conn =
        post(conn, "/scim/v2/Users", JSON.encode!(%{userName: existing.email, roles: [%{value: "Owner"}]}))

      assert json_response(conn, 201)["id"] == to_string(existing.id)
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(existing, org)
    end

    test "honors an explicit downgrade for an existing member", %{conn: conn, organization: org} do
      existing = user_fixture()
      :ok = Accounts.add_user_to_organization(existing, org, role: :admin)

      conn =
        post(conn, "/scim/v2/Users", JSON.encode!(%{userName: existing.email, roles: [%{value: "Viewer"}]}))

      assert json_response(conn, 201)["id"] == to_string(existing.id)
      assert %{name: "viewer"} = Accounts.get_user_role_in_organization(existing, org)
    end

    test "uses the enrollment default for new memberships without roles", %{conn: conn, organization: org} do
      {:ok, org} = Accounts.update_organization(org, %{sso_default_role: "viewer"})

      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: "new-viewer@example.com"}))

      body = json_response(conn, 201)
      assert {:ok, user} = SCIM.get_user(org, body["id"])
      assert %{name: "viewer"} = Accounts.get_user_role_in_organization(user, org)
    end

    test "rejects missing userName", %{conn: conn} do
      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{}))
      assert json_response(conn, 400)["scimType"] == "invalidValue"
    end

    test "rejects an invalid email", %{conn: conn} do
      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: "not-an-email"}))
      assert json_response(conn, 400)["scimType"] == "invalidValue"
    end

    test "attaches an existing Tuist user to the organization on POST", %{conn: conn, organization: org} do
      existing = user_fixture(email: "taken@example.com")
      refute Accounts.belongs_to_organization?(existing, org)

      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: "taken@example.com"}))

      body = json_response(conn, 201)
      assert body["userName"] == "taken@example.com"
      assert Accounts.belongs_to_organization?(existing, org)
    end

    test "returns conflict when active=false targets an existing non-member", %{conn: conn, organization: org} do
      existing = user_fixture(email: "inactive@example.com")
      refute Accounts.belongs_to_organization?(existing, org)

      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: "inactive@example.com", active: false}))

      assert json_response(conn, 409)["scimType"] == "uniqueness"
      refute Accounts.belongs_to_organization?(existing, org)
    end

    test "assigns the role from a roles string", %{conn: conn, organization: org} do
      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: "alice@example.com", roles: "admin"}))

      body = json_response(conn, 201)
      {:ok, user} = SCIM.get_user(org, body["id"])
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(user, org)
    end

    test "assigns the most privileged role when several are sent", %{conn: conn, organization: org} do
      conn =
        post(
          conn,
          "/scim/v2/Users",
          JSON.encode!(%{userName: "alice@example.com", roles: [%{value: "User"}, %{value: "Admin"}]})
        )

      body = json_response(conn, 201)
      {:ok, user} = SCIM.get_user(org, body["id"])
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(user, org)
    end
  end

  describe "PUT /Users/:id" do
    test "updates the role from a roles list", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})

      conn =
        put(
          conn,
          "/scim/v2/Users/#{user.id}",
          JSON.encode!(%{userName: "alice@example.com", active: true, roles: [%{value: "admin"}]})
        )

      assert json_response(conn, 200)
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(user, org)
    end

    test "updates the role from a roles string", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})

      conn =
        put(conn, "/scim/v2/Users/#{user.id}", JSON.encode!(%{userName: "alice@example.com", roles: "viewer"}))

      assert json_response(conn, 200)
      assert %{name: "viewer"} = Accounts.get_user_role_in_organization(user, org)
    end

    test "keeps the role when the payload has no roles", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com", role: :admin})

      conn = put(conn, "/scim/v2/Users/#{user.id}", JSON.encode!(%{userName: "alice@example.com", active: true}))

      assert json_response(conn, 200)
      assert %{name: "admin"} = Accounts.get_user_role_in_organization(user, org)
    end
  end

  describe "GET /Users" do
    test "returns a SCIM list response", %{conn: conn, organization: org} do
      {:ok, _} = SCIM.provision_user(org, %{user_name: "alice@example.com"})
      {:ok, _} = SCIM.provision_user(org, %{user_name: "bob@example.com"})

      conn = get(conn, "/scim/v2/Users")
      body = json_response(conn, 200)

      emails = Enum.map(body["Resources"], & &1["userName"])
      assert "alice@example.com" in emails
      assert "bob@example.com" in emails
      assert body["totalResults"] == length(body["Resources"])
    end

    test "filter by userName", %{conn: conn, organization: org} do
      {:ok, _} = SCIM.provision_user(org, %{user_name: "alice@example.com"})
      {:ok, _} = SCIM.provision_user(org, %{user_name: "bob@example.com"})

      conn = get(conn, ~s(/scim/v2/Users?filter=userName eq "alice@example.com"))
      body = json_response(conn, 200)

      assert body["totalResults"] == 1
      assert hd(body["Resources"])["userName"] == "alice@example.com"
    end

    test "rejects an unsupported filter", %{conn: conn} do
      conn = get(conn, "/scim/v2/Users?filter=foo bar baz")
      assert json_response(conn, 400)["scimType"] == "invalidFilter"
    end

    test "rejects unsupported filter attributes", %{conn: conn} do
      conn = get(conn, ~s(/scim/v2/Users?filter=displayName eq "Alice"))
      assert json_response(conn, 400)["scimType"] == "invalidFilter"
    end
  end

  describe "PATCH /Users/:id" do
    test "deactivates via replace active=false", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})

      body =
        JSON.encode!(%{
          schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
          Operations: [%{op: "replace", path: "active", value: false}]
        })

      conn = patch(conn, "/scim/v2/Users/#{user.id}", body)
      assert json_response(conn, 200)["active"] == false
      assert {:error, :not_found} = SCIM.get_user(org, user.id)
      assert Accounts.get_user_by_id(user.id).active == true
    end

    test "deactivates when Entra ID sends active as a string", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "entra@example.com"})

      body =
        JSON.encode!(%{
          schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
          Operations: [%{op: "Replace", path: "active", value: "False"}]
        })

      conn = patch(conn, "/scim/v2/Users/#{user.id}", body)
      assert json_response(conn, 200)["active"] == false
      assert {:error, :not_found} = SCIM.get_user(org, user.id)
    end
  end

  describe "operator email domain" do
    setup do
      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      %{operator_email: "x@#{Tuist.Environment.operator_email_domain()}"}
    end

    test "refuses to create an operator-domain user", %{conn: conn, operator_email: operator_email} do
      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: operator_email, active: true}))

      assert json_response(conn, 400)["scimType"] == "invalidValue"
      assert {:error, :not_found} = Accounts.get_user_by_email(operator_email)
    end

    test "refuses to rename a member into the operator domain", %{
      conn: conn,
      organization: org,
      operator_email: operator_email
    } do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "member@example.com"})

      body =
        JSON.encode!(%{
          schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
          Operations: [%{op: "replace", path: "userName", value: String.upcase(operator_email)}]
        })

      conn = patch(conn, "/scim/v2/Users/#{user.id}", body)

      assert json_response(conn, 400)["scimType"] == "invalidValue"
      assert Accounts.get_user_by_id(user.id).email == "member@example.com"
      refute Accounts.tuist_operator?(Accounts.get_user_by_id(user.id))
    end

    test "creates operator-domain users for an organization that DNS-verified that domain", %{
      operator_email: operator_email
    } do
      organization =
        organization_fixture(
          sso_provider: :oauth2,
          sso_organization_id: "https://idp.operator.example",
          sso_login_domain: Tuist.Environment.operator_email_domain(),
          sso_login_domain_verified_at: ~U[2026-01-01 00:00:00Z],
          oauth2_client_id: "client",
          oauth2_client_secret: "secret",
          oauth2_authorize_url: "https://idp.operator.example/authorize",
          oauth2_token_url: "https://idp.operator.example/token",
          oauth2_user_info_url: "https://idp.operator.example/userinfo"
        )

      {:ok, {_token, plaintext}} = SCIM.create_token(organization, %{name: "verified"})

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{plaintext}")
        |> put_req_header("content-type", "application/scim+json")
        |> post("/scim/v2/Users", JSON.encode!(%{userName: operator_email, active: true}))

      assert json_response(conn, 201)["userName"] == operator_email
    end

    test "still attaches an existing operator-domain user", %{
      conn: conn,
      organization: org,
      operator_email: operator_email
    } do
      existing = user_fixture(email: operator_email)

      conn = post(conn, "/scim/v2/Users", JSON.encode!(%{userName: operator_email, active: true}))

      assert json_response(conn, 201)["id"] == to_string(existing.id)
      assert Accounts.belongs_to_organization?(existing, org)
    end
  end

  describe "DELETE /Users/:id" do
    test "deactivates and removes from org", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})

      conn = delete(conn, "/scim/v2/Users/#{user.id}")
      assert response(conn, 204)

      assert {:error, :not_found} = SCIM.get_user(org, user.id)
      assert Accounts.get_user_by_id(user.id).active == true
    end
  end

  describe "discovery" do
    test "ServiceProviderConfig exposes the supported features", %{conn: conn} do
      conn = get(conn, "/scim/v2/ServiceProviderConfig")
      body = json_response(conn, 200)

      assert body["patch"]["supported"] == true
      assert body["filter"]["supported"] == true
      assert body["bulk"]["supported"] == false
    end

    test "ResourceTypes lists User and Group", %{conn: conn} do
      conn = get(conn, "/scim/v2/ResourceTypes")
      body = json_response(conn, 200)

      ids = MapSet.new(body["Resources"], & &1["id"])
      assert MapSet.equal?(ids, MapSet.new(["User", "Group"]))
    end
  end
end
