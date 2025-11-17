defmodule Tuist.Accounts.UserTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.User
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "create_changeset" do
    test "downcases the email" do
      # Given/When
      got = User.create_user_changeset(%User{}, %{email: "Test@Tuist.io"})

      # Then
      assert "test@tuist.io" == Ecto.Changeset.fetch_change!(got, :email)
    end

    test "validates password length" do
      # Given/When
      got = User.create_user_changeset(%User{}, %{password: "6789"})

      # Then
      assert got.valid? == false
      assert "should be at least 6 character(s)" in errors_on(got).password
    end

    test "validates password strength" do
      # Given/When
      got = User.create_user_changeset(%User{}, %{password: "6789"})

      # Then
      assert got.valid? == false
      assert "Avoid sequences" in errors_on(got).password
      assert "Add another word or two. Uncommon words are better." in errors_on(got).password
    end
  end

  describe "password_changeset/2" do
    test "validates the password strength" do
      # Given/When
      got = User.password_changeset(%User{}, %{password: "6789"})

      # Then
      assert got.valid? == false

      assert "Add another word or two. Uncommon words are better." in errors_on(got).password
      assert "Avoid sequences" in errors_on(got).password
    end
  end

  describe "gravatar_url/1" do
    test "generates the right avatar" do
      # When
      got = [email: "tuist@tuist.dev"] |> AccountsFixtures.user_fixture() |> User.gravatar_url()

      # Then
      assert got == "https://www.gravatar.com/avatar/20781daad983fcf18cbd592ae46aa57e?d=404"
    end
  end
end
