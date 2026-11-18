defmodule Tuist.Accounts.Workers.SecurityNotificationWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Bamboo.Test
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.UserNotifier
  alias Tuist.Accounts.Workers.SecurityNotificationWorker

  test "delivers each security event without putting credentials in job arguments" do
    user = user_fixture(preload: [:account])

    for {event, subject} <- [
          mfa_enabled: "Two-factor authentication enabled",
          mfa_disabled: "Two-factor authentication disabled",
          passkey_added: "Passkey added",
          passkey_removed: "Passkey removed",
          recovery_used: "Recovery code used",
          recovery_regenerated: "Recovery codes regenerated"
        ] do
      job = SecurityNotificationWorker.enqueue(user, event)
      assert job.args == %{"user_id" => user.id, "event" => to_string(event)}
      assert :ok = perform_job(SecurityNotificationWorker, job.args)
      assert_email_delivered_with(subject: subject, to: [nil: user.email])
    end
  end

  test "delivery failure is retryable and a later attempt delivers the recovery alert" do
    user = user_fixture(preload: [:account])
    job = SecurityNotificationWorker.enqueue(user, :recovery_used)

    stub(UserNotifier, :deliver_recovery_notification, fn _, _ -> {:error, :delivery_unavailable} end)
    assert {:error, :delivery_unavailable} = perform_job(SecurityNotificationWorker, job.args)
    assert_enqueued(worker: SecurityNotificationWorker, args: job.args)

    stub(UserNotifier, :deliver_recovery_notification, fn user, event ->
      Mimic.call_original(UserNotifier, :deliver_recovery_notification, [user, event])
    end)

    assert :ok = perform_job(SecurityNotificationWorker, job.args)
    assert_email_delivered_with(subject: "Recovery code used", to: [nil: user.email])
  end
end
