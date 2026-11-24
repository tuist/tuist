defmodule Tuist.Accounts.Workers.CredentialRotationNoticeWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Bamboo.Test

  alias Tuist.Accounts
  alias Tuist.Accounts.Workers.CredentialRotationNoticeWorker
  alias Tuist.Release
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    admin = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    Accounts.add_user_to_organization(admin, organization, role: :admin)
    Accounts.add_user_to_organization(member, organization, role: :user)

    %{account: organization.account, admin: admin, member: member}
  end

  defp args(account, user, kind),
    do: %{notice_id: Ecto.UUID.generate(), account_id: account.id, user_id: user.id, kind: kind}

  test "emails an admin that their credentials were revoked and where to create new ones", %{
    account: account,
    admin: admin
  } do
    assert :ok = perform_job(CredentialRotationNoticeWorker, args(account, admin, :revoked))

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "We revoked the Tuist credentials of #{account.name}",
      text_body: ~r{/#{account.name}/settings/tokens}
    )
  end

  test "asks an admin to rotate and links the incident write-up", %{account: account, admin: admin} do
    job_args = Map.put(args(account, admin, :rotate), :details_url, "https://tuist.dev/blog/incident")

    assert :ok = perform_job(CredentialRotationNoticeWorker, job_args)

    assert_email_delivered_with(
      to: [nil: admin.email],
      subject: "Rotate the Tuist credentials of #{account.name}",
      text_body: ~r{https://tuist.dev/blog/incident}
    )
  end

  test "emails nobody who is not an admin of the account", %{account: account, member: member} do
    assert :ok = perform_job(CredentialRotationNoticeWorker, args(account, member, :rotate))

    assert_no_emails_delivered()
  end

  describe "Release.send_credential_rotation_notice/2" do
    test "queues one notice per admin of the account", %{account: account, admin: admin, member: member} do
      assert %{queued: queued, notice_id: notice_id} =
               Release.send_credential_rotation_notice(account.id, kind: :revoked)

      recipients =
        [worker: CredentialRotationNoticeWorker]
        |> all_enqueued()
        |> Enum.map(& &1.args["user_id"])

      # The organization's creator is an admin too.
      assert queued == 2
      assert admin.id in recipients
      refute member.id in recipients
      assert Enum.all?(all_enqueued(worker: CredentialRotationNoticeWorker), &(&1.args["notice_id"] == notice_id))
    end

    test "resuming a sending queues nothing twice", %{account: account} do
      %{notice_id: notice_id} = Release.send_credential_rotation_notice(account.id, kind: :rotate)

      assert %{queued: 0} = Release.send_credential_rotation_notice(account.id, kind: :rotate, notice_id: notice_id)
      assert length(all_enqueued(worker: CredentialRotationNoticeWorker)) == 2
    end

    test "reaches personal account owners when sent to everyone" do
      user = AccountsFixtures.user_fixture(preload: [:account])

      Release.send_credential_rotation_notice(:everything, kind: :rotate)

      assert_enqueued(worker: CredentialRotationNoticeWorker, args: %{account_id: user.account.id, user_id: user.id})
    end
  end
end
