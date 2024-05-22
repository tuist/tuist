defmodule TuistCloud.Accounts.UserTest do
  use ExUnit.Case
  alias TuistCloud.Accounts.User

  describe "create_changeset" do
    test "downcases the email" do
      # Given/When
      got = User.create_user_changeset(%User{}, %{email: "Test@Tuist.io"})

      # Then
      assert "test@tuist.io" == Ecto.Changeset.fetch_change!(got, :email)
    end
  end
end
