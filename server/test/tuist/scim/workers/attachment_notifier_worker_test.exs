defmodule Tuist.SCIM.Workers.AttachmentNotifierWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.UserNotifier
  alias Tuist.SCIM.Workers.AttachmentNotifierWorker

  describe "perform/1" do
    test "delivers the SCIM attachment email to the user" do
      organization = organization_fixture(preload: [:account])
      user = user_fixture(email: "attached@example.com")

      expect(UserNotifier, :deliver_scim_organization_attachment, fn delivered_user, delivered_org ->
        assert delivered_user.id == user.id
        assert delivered_org.id == organization.id
        assert delivered_org.account.name == organization.account.name
        :ok
      end)

      assert :ok =
               perform_job(AttachmentNotifierWorker, %{
                 "user_id" => user.id,
                 "organization_id" => organization.id
               })
    end

    test "discards the job when the user no longer exists" do
      organization = organization_fixture()

      assert {:discard, :user_or_organization_gone} =
               perform_job(AttachmentNotifierWorker, %{
                 "user_id" => -1,
                 "organization_id" => organization.id
               })
    end

    test "discards the job when the organization no longer exists" do
      user = user_fixture()

      assert {:discard, :user_or_organization_gone} =
               perform_job(AttachmentNotifierWorker, %{
                 "user_id" => user.id,
                 "organization_id" => -1
               })
    end
  end
end
