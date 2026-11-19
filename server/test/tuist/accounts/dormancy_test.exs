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

  defp signed_in_days_ago(user, days) do
    at = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -days * 24 * 60 * 60, :second)
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [last_sign_in_at: at])
    Accounts.get_user_by_id(user.id)
  end

  defp operator_fixture(opts \\ []) do
    email = "operator-#{TuistTestSupport.Utilities.unique_integer()}@#{@domain}"

    user =
      AccountsFixtures.user_fixture([email: email] ++ Keyword.take(opts, [:created_at]))

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

    test "disconnects live sockets when it disables an account" do
      # Given a connected LiveView, which holds its authenticated user in
      # assigns and never repeats the session lookup, so deleting the token
      # alone would leave it working.
      user = operator_fixture(last_sign_in_days_ago: 200)
      token = Accounts.generate_user_session_token(user)
      live_socket_id = UserToken.live_socket_id(token)
      Phoenix.PubSub.subscribe(Tuist.PubSub, live_socket_id)

      # When
      assert user.id in Dormancy.sweep(operator_email_domain: @domain).disabled

      # Then
      assert_receive %Phoenix.Socket.Broadcast{topic: ^live_socket_id, event: "disconnect"}
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
      candidates = Dormancy.list_disable_candidates(NaiveDateTime.utc_now(:second), {@domain, []})
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
      candidates = Dormancy.list_scrub_candidates(NaiveDateTime.utc_now(:second), {@domain, []})
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

    test "disables dormant members of internal organizations on any email domain" do
      # Given a bot account in an organization Tuist owns, and an equally
      # dormant member of a customer organization.
      internal =
        AccountsFixtures.organization_fixture(name: "TuistInternal#{TuistTestSupport.Utilities.unique_integer()}")

      customer = AccountsFixtures.organization_fixture()
      bot = signed_in_days_ago(AccountsFixtures.user_fixture(email: "bot@example.com"), 200)
      outsider = signed_in_days_ago(AccountsFixtures.user_fixture(email: "someone@example.org"), 200)
      Accounts.add_user_to_organization(bot, internal)
      Accounts.add_user_to_organization(outsider, customer)
      handles = [String.downcase(internal.account.name)]

      # When
      result = Dormancy.sweep(operator_email_domain: @domain, internal_organization_handles: handles)

      # Then
      assert bot.id in result.disabled
      refute outsider.id in result.disabled
      refute Accounts.get_user_by_id(bot.id).active
      assert Accounts.get_user_by_id(outsider.id).active
    end

    test "a scrubbed member of an internal organization is not reprocessed" do
      # Given a scrubbed member, whose role row survives the scrub.
      internal = AccountsFixtures.organization_fixture()
      bot = signed_in_days_ago(AccountsFixtures.user_fixture(email: "bot@example.com"), 400)
      Accounts.add_user_to_organization(bot, internal)
      bot |> disable() |> Dormancy.scrub()

      # When
      result =
        Dormancy.sweep(operator_email_domain: @domain, internal_organization_handles: [internal.account.name])

      # Then
      refute bot.id in result.scrubbed
      refute bot.id in result.clock_started
      refute bot.id in result.unknown_activity
    end

    test "ages accounts that never signed in from the activity-tracking floor" do
      # Given two operators that never authenticated: one created before
      # tracking began, one created and left unused well after it.
      floor = Dormancy.activity_tracking_started_at()
      before = operator_fixture(created_at: DateTime.from_naive!(NaiveDateTime.add(floor, -300, :day), "Etc/UTC"))
      unused = operator_fixture(created_at: DateTime.from_naive!(NaiveDateTime.add(floor, 100, :day), "Etc/UTC"))

      # When the sweep runs 200 days after tracking began
      result = Dormancy.sweep(operator_email_domain: @domain, now: NaiveDateTime.add(floor, 200, :day))

      # Then the older account is past the threshold measured from the floor,
      # not from its creation date or from "never", and the newer one is not.
      assert before.id in result.disabled
      refute unused.id in result.disabled
      assert unused.id in result.unknown_activity
    end

    test "does not disable never-signed-in accounts before the floor has aged" do
      # Given an operator created long before tracking began
      floor = Dormancy.activity_tracking_started_at()
      user = operator_fixture(created_at: DateTime.from_naive!(NaiveDateTime.add(floor, -800, :day), "Etc/UTC"))

      # When the sweep runs one day short of the threshold after the floor
      result = Dormancy.sweep(operator_email_domain: @domain, now: NaiveDateTime.add(floor, 179, :day))

      # Then
      refute user.id in result.disabled
    end

    test "a scrubbed user can no longer authenticate" do
      # Given
      user = operator_fixture(last_sign_in_days_ago: 400)
      token = AccountsFixtures.user_access_token(user)
      user |> disable() |> Dormancy.scrub()

      # When / Then
      assert is_nil(Tuist.Authentication.authenticated_subject(token))
    end
  end
end
