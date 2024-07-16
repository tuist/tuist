defmodule Tuist.OrganizationTest do
  alias Tuist.Accounts.Organization
  use Tuist.DataCase
  use Mimic

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
      Organization.create_changeset(%Organization{}, %{
        sso_provider: :google,
        sso_organization_id: "tuist.io"
      })
      |> Repo.insert()

      {:ok, organization} =
        Organization.create_changeset(%Organization{})
        |> Repo.insert()

      {:error, changeset} =
        Organization.update_changeset(organization, %{
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
  end
end
