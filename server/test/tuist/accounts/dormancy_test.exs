defmodule Tuist.Accounts.DormancyTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use TuistTestSupport.Cases.StubCase, billing: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Dormancy
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserToken
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @domain "tuist.dev"

  defp operator_fixture(opts \\ []) do
    email = "operator-#{TuistTestSupport.Utilities.unique_integer()}@#{@domain}"
    user = AccountsFixtures.user_fixture(email: email)

    case Keyword.get(opts, :last_sign_in_days_ago) do
      nil ->
        user

      days ->
        at = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -days * 24 * 60 * 60, :second)
        Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_sign_in_at: at])
        Accounts.get_user_by_id(user.id)
    end
  end

  defp disable(user) do
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [active: false])
    Accounts.get_user_by_id(user.id)
  end

  describe "sweep/1" do
    test "disables operator accounts inactive for 180 days" do
      # Given
      dormant = operator_fixture(last_sign_in_days_ago: 200)
      recent = operator_fixture(last_sign_in_days_ago: 30)

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      assert dormant.id in result.disabled
      refute recent.id in result.disabled
      refute Accounts.get_user_by_id(dormant.id).active
      assert Accounts.get_user_by_id(recent.id).active
    end

    test "does not touch accounts with no recorded activity" do
      # Given
      never = operator_fixture()

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      assert never.id in result.unknown_activity
      refute never.id in result.disabled
      refute never.id in result.scrubbed
      assert Accounts.get_user_by_id(never.id).active
    end

    test "does not touch accounts outside the operator domain" do
      # Given
      customer = AccountsFixtures.user_fixture(email: "someone@example.com")

      Repo.update_all(
        from(u in User, where: u.id == ^customer.id),
        set: [last_sign_in_at: NaiveDateTime.add(NaiveDateTime.utc_now(:second), -400, :day)]
      )

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      refute customer.id in result.disabled
      refute customer.id in result.scrubbed
      assert Accounts.get_user_by_id(customer.id).active
    end

    test "scrubs the identity of accounts disabled and inactive for 365 days" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      AccountsFixtures.oauth2_identity_fixture(user: user)
      Accounts.generate_user_session_token(user)
      user = disable(user)

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      assert user.id in result.scrubbed

      scrubbed = Accounts.get_user_by_id(user.id)
      assert scrubbed.email == "deleted-user-#{user.id}@invalid"
      assert scrubbed.encrypted_password == ""
      refute scrubbed.active
      refute scrubbed.token == user.token
      assert Repo.all(from(o in Oauth2Identity, where: o.user_id == ^user.id)) == []
      assert Repo.all(from(t in UserToken, where: t.user_id == ^user.id)) == []
    end

    test "does not scrub an account that is still active" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      assert user.id in result.disabled
      refute user.id in result.scrubbed
      assert Accounts.get_user_by_id(user.id).email == user.email
    end

    test "a scrubbed account is not reprocessed on the next sweep" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      user |> disable() |> Dormancy.scrub()

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      refute user.id in result.scrubbed
      refute user.id in result.disabled
    end

    test "a scrubbed user can no longer authenticate" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      token = user.token
      user |> disable() |> Dormancy.scrub()

      # When / Then
      assert is_nil(Accounts.get_user_by_token(token))
    end
  end
end
