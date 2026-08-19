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

  # Disabling with a clock start far enough back that the account has served
  # the checkpoint. `disabled_days_ago: 0` models an account disabled just
  # now, which is what an interrupted run leaves behind.
  defp disable(user, opts \\ []) do
    days = Keyword.get(opts, :disabled_days_ago, 400)
    at = DateTime.add(DateTime.utc_now(:second), -days * 24 * 60 * 60, :second)

    Repo.update_all(
      from(u in User, where: u.id == ^user.id),
      set: [active: false, disabled_at: at]
    )

    Accounts.get_user_by_id(user.id)
  end

  defp disable_without_clock(user) do
    Repo.update_all(
      from(u in User, where: u.id == ^user.id),
      set: [active: false, disabled_at: nil]
    )

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

    test "does not scrub an account disabled by the same sweep on the next run" do
      # Given a run that disabled the account and then died, the retry must
      # not treat "currently disabled" as having served the checkpoint.
      user = operator_fixture(last_sign_in_days_ago: 400)
      assert user.id in Dormancy.sweep(operator_email_domain: @domain).disabled

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      refute user.id in result.scrubbed
      assert Accounts.get_user_by_id(user.id).email == user.email
    end

    test "does not scrub an account that has not served the disabled checkpoint" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      disable(user, disabled_days_ago: Dormancy.disabled_grace_days() - 1)

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      refute user.id in result.scrubbed
      assert Accounts.get_user_by_id(user.id).email == user.email
    end

    test "starts the checkpoint for a disabled account that has no clock" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      disable_without_clock(user)

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      assert user.id in result.clock_started
      refute user.id in result.scrubbed
      assert Accounts.get_user_by_id(user.id).disabled_at
    end

    test "does not disable an account that signs in after being selected" do
      # Given a sweep that has already chosen its candidates, and the account
      # coming back to life before the write lands.
      user = operator_fixture(last_sign_in_days_ago: 200)
      candidates = Dormancy.list_disable_candidates(NaiveDateTime.utc_now(:second), @domain)
      assert user.id in Enum.map(candidates, & &1.id)

      Repo.update_all(
        from(u in User, where: u.id == ^user.id),
        set: [last_sign_in_at: NaiveDateTime.utc_now(:second)]
      )

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      refute user.id in result.disabled
      assert Accounts.get_user_by_id(user.id).active
    end

    test "does not scrub an account that is re-enabled after being selected" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      disable(user)
      candidates = Dormancy.list_scrub_candidates(NaiveDateTime.utc_now(:second), @domain)
      assert user.id in Enum.map(candidates, & &1.id)

      Repo.update_all(from(u in User, where: u.id == ^user.id), set: [active: true])

      # When
      result = Dormancy.sweep(operator_email_domain: @domain)

      # Then
      refute user.id in result.scrubbed
      assert Accounts.get_user_by_id(user.id).email == user.email
    end

    test "reports work left when the clock-start batch fills the window" do
      # Given
      for _ <- 1..3 do
        u = operator_fixture(last_sign_in_days_ago: 10)
        disable_without_clock(u)
      end

      # When
      result = Dormancy.sweep(operator_email_domain: @domain, limit: 2)

      # Then
      assert length(result.clock_started) == 2
      assert result.more_pending
    end

    test "bounds how many accounts one run actions and says work is left" do
      # Given
      users = for _ <- 1..3, do: operator_fixture(last_sign_in_days_ago: 200)

      # When
      result = Dormancy.sweep(operator_email_domain: @domain, limit: 2)

      # Then
      assert length(result.disabled) == 2
      assert result.more_pending

      remaining = Dormancy.sweep(operator_email_domain: @domain, limit: 2)
      refute remaining.more_pending

      for user <- users, do: refute(Accounts.get_user_by_id(user.id).active)
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
