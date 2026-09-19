defmodule TuistWeb.UserSessionControllerAuthOutcomeTest do
  # Not async: asserting on these records means lowering the global Logger
  # level, which is shared state. ExUnit runs sync tests after the async ones,
  # so nothing else is in flight while it is lowered.
  use TuistTestSupport.Cases.ConnCase, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    %{user: user_fixture(preload: [:account])}
  end

  describe "POST /users/log_in" do
    # Every outcome of a sign-in attempt redirects, a wrong password just as
    # much as a success, so the response status cannot tell them apart.
    # Reviewing authentication depends on the explicit outcome these assert.
    test "records a failed sign-in as an explicit outcome", %{conn: conn, user: user} do
      log =
        capture_info_log(fn ->
          post(conn, ~p"/users/log_in", %{
            "user" => %{"email" => user.email, "password" => "not-the-password"}
          })
        end)

      assert log =~ "authentication attempt"
      assert log =~ "auth_outcome=invalid_credentials"
    end

    test "records a successful sign-in as an explicit outcome", %{conn: conn, user: user} do
      log =
        capture_info_log(fn ->
          post(conn, ~p"/users/log_in", %{
            "user" => %{"email" => user.email, "password" => valid_user_password()}
          })
        end)

      assert log =~ "auth_outcome=success"
    end
  end

  defp capture_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      Logger.configure(level: previous)
    end
  end
end
