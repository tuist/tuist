defmodule Tuist.OrganizationTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Organization

  @okta_attrs %{
    sso_provider: :okta,
    sso_organization_id: "tuist.okta.com",
    oauth2_client_id: "client-id",
    oauth2_encrypted_client_secret: "client-secret",
    oauth2_authorize_url: "https://tuist.okta.com/oauth2/v1/authorize",
    oauth2_token_url: "https://tuist.okta.com/oauth2/v1/token",
    oauth2_user_info_url: "https://tuist.okta.com/oauth2/v1/userinfo"
  }

  @oauth2_attrs %{
    sso_provider: :oauth2,
    sso_organization_id: "https://auth.example.com",
    oauth2_client_id: "client-id",
    oauth2_encrypted_client_secret: "client-secret",
    oauth2_authorize_url: "https://auth.example.com/oauth2/authorize",
    oauth2_token_url: "https://auth.example.com/oauth2/token",
    oauth2_user_info_url: "https://auth.example.com/oauth2/userinfo"
  }

  describe "create_changeset/2" do
    test "sso_provider cannot be github" do
      changeset =
        Organization.create_changeset(%Organization{}, %{
          sso_provider: :github,
          sso_organization_id: "tuist.io"
        })

      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).sso_provider
    end

    test "sso_provider and sso_organization_id must be exclusive" do
      Organization.create_changeset(%Organization{}, %{
        sso_provider: :github,
        sso_organization_id: "tuist.io"
      })

      changeset =
        Organization.create_changeset(%Organization{}, %{
          sso_provider: :github,
          sso_organization_id: "tuist.io"
        })

      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).sso_provider
    end

    test "changeset is valid when sso_provider is google" do
      changeset =
        Organization.create_changeset(%Organization{}, %{
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        })

      assert changeset.valid? == true
    end

    test "changeset is valid when sso_provider is okta" do
      changeset = Organization.create_changeset(%Organization{}, @okta_attrs)

      assert changeset.valid? == true
    end

    test "requires all oauth2 fields for okta provider" do
      changeset =
        Organization.create_changeset(%Organization{}, %{
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).oauth2_client_id
      assert "can't be blank" in errors_on(changeset).oauth2_encrypted_client_secret
      assert "can't be blank" in errors_on(changeset).oauth2_authorize_url
      assert "can't be blank" in errors_on(changeset).oauth2_token_url
      assert "can't be blank" in errors_on(changeset).oauth2_user_info_url
    end

    test "changeset is valid when sso_provider is oauth2" do
      changeset = Organization.create_changeset(%Organization{}, @oauth2_attrs)

      assert changeset.valid? == true
    end

    test "normalizes the oauth2 site on create" do
      changeset =
        Organization.create_changeset(
          %Organization{},
          Map.merge(@oauth2_attrs, %{
            sso_organization_id: " https://auth.example.com/ ",
            oauth2_authorize_url: " https://auth.example.com/oauth2/authorize ",
            oauth2_token_url: " https://auth.example.com/oauth2/token ",
            oauth2_user_info_url: " https://auth.example.com/oauth2/userinfo "
          })
        )

      assert Ecto.Changeset.get_change(changeset, :sso_organization_id) == "https://auth.example.com"

      assert Ecto.Changeset.get_change(changeset, :oauth2_authorize_url) ==
               "https://auth.example.com/oauth2/authorize"

      assert Ecto.Changeset.get_change(changeset, :oauth2_token_url) ==
               "https://auth.example.com/oauth2/token"

      assert Ecto.Changeset.get_change(changeset, :oauth2_user_info_url) ==
               "https://auth.example.com/oauth2/userinfo"
    end

    test "validates the oauth2 site URL on create" do
      changeset =
        Organization.create_changeset(
          %Organization{},
          Map.put(@oauth2_attrs, :sso_organization_id, "not-a-url")
        )

      assert changeset.valid? == false
      assert "must be a valid URL" in errors_on(changeset).sso_organization_id
    end

    test "validates the oauth2 endpoint URLs on create" do
      changeset =
        Organization.create_changeset(
          %Organization{},
          Map.put(@oauth2_attrs, :oauth2_authorize_url, "not-a-url")
        )

      assert changeset.valid? == false
      assert "must be a valid URL" in errors_on(changeset).oauth2_authorize_url
    end

    test "requires the oauth2 fields on create" do
      changeset =
        Organization.create_changeset(%Organization{}, %{
          sso_provider: :oauth2
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).sso_organization_id
      assert "can't be blank" in errors_on(changeset).oauth2_client_id
      assert "can't be blank" in errors_on(changeset).oauth2_encrypted_client_secret
      assert "can't be blank" in errors_on(changeset).oauth2_authorize_url
      assert "can't be blank" in errors_on(changeset).oauth2_token_url
      assert "can't be blank" in errors_on(changeset).oauth2_user_info_url
    end
  end

  describe "update_changeset/2" do
    test "sso_provider cannot be github" do
      changeset =
        Organization.update_changeset(%Organization{}, %{
          sso_provider: :github,
          sso_organization_id: "tuist.io"
        })

      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).sso_provider
    end

    test "sso_provider and sso_organization_id must be exclusive" do
      %Organization{}
      |> Organization.create_changeset(%{
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      })
      |> Repo.insert()

      {:ok, organization} =
        %Organization{}
        |> Organization.create_changeset()
        |> Repo.insert()

      {:error, changeset} =
        organization
        |> Organization.update_changeset(%{
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        })
        |> Repo.update()

      assert changeset.valid? == false

      assert "SSO provider and SSO organization ID must be unique. Make sure no other organization has the same SSO provider and SSO organization ID." in errors_on(
               changeset
             ).sso_provider
    end

    test "changeset is valid when sso_provider is google" do
      changeset =
        Organization.update_changeset(%Organization{}, %{
          sso_provider: :google,
          sso_organization_id: "tuist.io"
        })

      assert changeset.valid? == true
    end

    test "changeset is valid when sso_provider is okta" do
      changeset =
        Organization.update_changeset(%Organization{}, Map.put(@okta_attrs, :sso_organization_id, "dev.okta.com"))

      assert changeset.valid? == true
    end

    test "changeset is valid when sso_provider is oauth2" do
      changeset = Organization.update_changeset(%Organization{}, @oauth2_attrs)

      assert changeset.valid? == true
    end

    test "normalizes the oauth2 site on update" do
      changeset =
        Organization.update_changeset(
          %Organization{},
          Map.merge(@oauth2_attrs, %{
            sso_organization_id: " https://auth.example.com/ ",
            oauth2_authorize_url: " https://auth.example.com/oauth2/authorize ",
            oauth2_token_url: " https://auth.example.com/oauth2/token ",
            oauth2_user_info_url: " https://auth.example.com/oauth2/userinfo "
          })
        )

      assert Ecto.Changeset.get_change(changeset, :sso_organization_id) == "https://auth.example.com"

      assert Ecto.Changeset.get_change(changeset, :oauth2_authorize_url) ==
               "https://auth.example.com/oauth2/authorize"

      assert Ecto.Changeset.get_change(changeset, :oauth2_token_url) ==
               "https://auth.example.com/oauth2/token"

      assert Ecto.Changeset.get_change(changeset, :oauth2_user_info_url) ==
               "https://auth.example.com/oauth2/userinfo"
    end

    test "validates the oauth2 site URL on update" do
      changeset =
        Organization.update_changeset(
          %Organization{},
          Map.put(@oauth2_attrs, :sso_organization_id, "notaurl")
        )

      assert changeset.valid? == false
      assert "must be a valid URL" in errors_on(changeset).sso_organization_id
    end

    test "validates the oauth2 endpoint URLs on update" do
      changeset =
        Organization.update_changeset(
          %Organization{},
          Map.put(@oauth2_attrs, :oauth2_token_url, "not-a-url")
        )

      assert changeset.valid? == false
      assert "must be a valid URL" in errors_on(changeset).oauth2_token_url
    end

    test "requires the oauth2 fields on update when no secret exists" do
      changeset =
        Organization.update_changeset(%Organization{}, %{
          sso_provider: :oauth2
        })

      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).sso_organization_id
      assert "can't be blank" in errors_on(changeset).oauth2_client_id
      assert "can't be blank" in errors_on(changeset).oauth2_encrypted_client_secret
      assert "can't be blank" in errors_on(changeset).oauth2_authorize_url
      assert "can't be blank" in errors_on(changeset).oauth2_token_url
      assert "can't be blank" in errors_on(changeset).oauth2_user_info_url
    end

    test "does not require the oauth2 secret on update when already persisted" do
      changeset =
        Organization.update_changeset(
          %Organization{oauth2_encrypted_client_secret: "existing-secret"},
          @oauth2_attrs
        )

      assert changeset.valid? == true
    end
  end
end
