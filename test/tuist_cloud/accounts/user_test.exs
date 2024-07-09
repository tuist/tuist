defmodule TuistCloud.Accounts.UserTest do
  use TuistCloud.DataCase
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.Accounts.User

  describe "create_changeset" do
    test "downcases the email" do
      # Given/When
      got = User.create_user_changeset(%User{}, %{email: "Test@Tuist.io"})

      # Then
      assert "test@tuist.io" == Ecto.Changeset.fetch_change!(got, :email)
    end
  end

  describe "gravatar_url/1" do
    test "generates the right avatar" do
      # When
      got = AccountsFixtures.user_fixture(email: "tuist@tuist.io") |> User.gravatar_url()

      # Then
      assert got == "https://www.gravatar.com/avatar/0f3e9af754a1574f7b5fb3ab36e9b0b8"
    end
  end
end
