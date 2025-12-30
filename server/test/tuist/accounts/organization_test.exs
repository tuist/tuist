defmodule Tuist.OrganizationTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Organization

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
      changeset =
        Organization.create_changeset(%Organization{}, %{
          sso_provider: :okta,
          sso_organization_id: "tuist.okta.com"
        })

      assert changeset.valid? == true
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
        Organization.update_changeset(%Organization{}, %{
          sso_provider: :okta,
          sso_organization_id: "dev.okta.com"
        })

      assert changeset.valid? == true
    end
  end
end
