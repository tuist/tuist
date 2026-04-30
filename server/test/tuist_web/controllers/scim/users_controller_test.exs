defmodule TuistWeb.SCIM.UsersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

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
      conn = post(conn, "/scim/v2/Users", Jason.encode!(%{userName: "alice@example.com", active: true}))

      body = json_response(conn, 201)
      assert body["userName"] == "alice@example.com"
      assert body["active"] == true
      assert is_binary(body["id"])
      assert hd(get_resp_header(conn, "location")) =~ "/scim/v2/Users/#{body["id"]}"
    end

    test "rejects missing userName", %{conn: conn} do
      conn = post(conn, "/scim/v2/Users", Jason.encode!(%{}))
      assert json_response(conn, 400)["scimType"] == "invalidValue"
    end

    test "rejects an invalid email", %{conn: conn} do
      conn = post(conn, "/scim/v2/Users", Jason.encode!(%{userName: "not-an-email"}))
      assert json_response(conn, 400)["scimType"] == "invalidValue"
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
  end

  describe "PATCH /Users/:id" do
    test "deactivates via replace active=false", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})

      body =
        Jason.encode!(%{
          schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
          Operations: [%{op: "replace", path: "active", value: false}]
        })

      conn = patch(conn, "/scim/v2/Users/#{user.id}", body)
      assert json_response(conn, 200)["active"] == false
      assert {:error, :not_found} = SCIM.get_user(org, user.id)
    end
  end

  describe "DELETE /Users/:id" do
    test "deactivates and removes from org", %{conn: conn, organization: org} do
      {:ok, user} = SCIM.provision_user(org, %{user_name: "alice@example.com"})

      conn = delete(conn, "/scim/v2/Users/#{user.id}")
      assert response(conn, 204)

      assert {:error, :not_found} = SCIM.get_user(org, user.id)
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
