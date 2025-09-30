defmodule Tuist.InvitationTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts.Invitation
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_changeset" do
    test "ensures the token is present" do
      # Given
      invitation = %Invitation{}

      # When
      got = Invitation.create_changeset(invitation, %{})

      # Then
      assert "can't be blank" in errors_on(got).token
    end

    test "ensures the invitee_email is present" do
      # Given
      invitation = %Invitation{}

      # When
      got = Invitation.create_changeset(invitation, %{})

      # Then
      assert "can't be blank" in errors_on(got).invitee_email
    end

    test "ensures the inviter_id is present" do
      # Given
      invitation = %Invitation{}

      # When
      got = Invitation.create_changeset(invitation, %{})

      # Then
      assert "can't be blank" in errors_on(got).inviter_id
    end

    test "ensures the organization_id is present" do
      # Given
      invitation = %Invitation{}

      # When
      got = Invitation.create_changeset(invitation, %{})

      # Then
      assert "can't be blank" in errors_on(got).organization_id
    end

    test "ensures that the token is unique" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      changeset =
        Invitation.create_changeset(%Invitation{}, %{
          token: "token",
          invitee_email: "test@tuist.io",
          inviter_id: user.id,
          organization_id: organization.id
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        Repo.insert(
          Invitation.create_changeset(%Invitation{}, %{
            token: "new-token",
            invitee_email: "test@tuist.io",
            inviter_id: user.id,
            organization_id: organization.id
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).invitee_email
    end

    test "ensures that the invitee_email and organization_id are unique" do
      # Given
      user = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture()

      changeset =
        Invitation.create_changeset(%Invitation{}, %{
          token: "token",
          invitee_email: "test@tuist.io",
          inviter_id: user.id,
          organization_id: organization.id
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        Repo.insert(
          Invitation.create_changeset(%Invitation{}, %{
            token: "token-two",
            invitee_email: "test@tuist.io",
            inviter_id: user.id,
            organization_id: organization.id
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).invitee_email
    end

    test "downcases invitee_email" do
      # Given
      invitation = %Invitation{}

      # When
      changeset =
        Invitation.create_changeset(invitation, %{
          token: "test-token",
          invitee_email: "TEST@TUIST.IO",
          inviter_id: 1,
          organization_id: 1
        })

      # Then
      assert changeset.changes.invitee_email == "test@tuist.io"
    end
  end
end
