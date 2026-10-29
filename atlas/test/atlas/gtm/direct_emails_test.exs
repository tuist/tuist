defmodule Atlas.GTM.DirectEmailsTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.Audit.Activity
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.DirectEmails
  alias Atlas.GTM.Workers.DeliverDirectEmail

  @attrs %{
    "recipient_email" => "recipient@example.com",
    "subject" => "Your Tuist pricing is changing",
    "body_markdown" => "Your price changes on 22 October 2026."
  }

  test "queues a delivery and its job" do
    assert {:ok, %{delivery: delivery, duplicate: false}} = DirectEmails.queue(@attrs)

    assert delivery.kind == "direct"
    assert delivery.status == "pending"
    assert delivery.recipient_email == "recipient@example.com"
    assert delivery.metadata["body_markdown"] == "Your price changes on 22 October 2026."
    refute delivery.broadcast_id
    refute delivery.subscriber_id
    refute delivery.audience_id

    assert_enqueued(worker: DeliverDirectEmail, args: %{"delivery_id" => delivery.id})
  end

  test "records the account the notice belongs to" do
    # `accounts.account_key` is uniquely indexed, so a literal shared with
    # another test module would serialize on its uncommitted index entry.
    account =
      %Account{}
      |> Account.changeset(%{
        account_key: "account-#{System.unique_integer([:positive])}",
        name: "Acme",
        segment: :customer
      })
      |> Repo.insert!()

    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(Map.put(@attrs, "account", account))

    assert delivery.metadata["account_id"] == account.id
    assert delivery.metadata["account_key"] == account.account_key
  end

  test "trims the recipient, subject, and sender" do
    assert {:ok, %{delivery: delivery}} =
             DirectEmails.queue(%{
               "recipient_email" => "  recipient@example.com  ",
               "recipient_name" => "  Riley  ",
               "subject" => "  A notice  ",
               "body_markdown" => "Hello.",
               "from_email" => "  billing@tuist.dev  "
             })

    assert delivery.recipient_email == "recipient@example.com"
    assert delivery.recipient_name == "Riley"
    assert delivery.subject == "A notice"
    assert delivery.metadata["from_email"] == "billing@tuist.dev"
  end

  test "accepts atom keys" do
    assert {:ok, %{delivery: delivery}} =
             DirectEmails.queue(%{
               recipient_email: "recipient@example.com",
               subject: "A notice",
               body_markdown: "Hello."
             })

    assert delivery.subject == "A notice"
  end

  test "returns the queued delivery instead of sending twice on a retry" do
    assert {:ok, first} = DirectEmails.queue(@attrs)
    assert {:ok, second} = DirectEmails.queue(@attrs)

    assert second.duplicate
    assert second.delivery.id == first.delivery.id
    assert Repo.aggregate(from(d in Delivery, where: d.kind == "direct"), :count) == 1
  end

  test "treats a changed body as a new send rather than a duplicate" do
    assert {:ok, first} = DirectEmails.queue(@attrs)
    assert {:ok, second} = DirectEmails.queue(Map.put(@attrs, "body_markdown", "Corrected figures."))

    refute second.duplicate
    assert second.delivery.id != first.delivery.id
  end

  test "sends again once the earlier delivery fell outside the dedupe window" do
    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(@attrs)

    long_ago = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second) |> DateTime.to_naive()
    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [inserted_at: long_ago])

    assert {:ok, %{duplicate: false}} = DirectEmails.queue(@attrs)
  end

  test "does not treat a failed delivery as a duplicate" do
    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(@attrs)
    Repo.update_all(from(d in Delivery, where: d.id == ^delivery.id), set: [status: "failed"])

    assert {:ok, %{duplicate: false}} = DirectEmails.queue(@attrs)
  end

  test "stores the CC addresses on the delivery" do
    assert {:ok, %{delivery: delivery}} =
             DirectEmails.queue(Map.put(@attrs, "cc_emails", ["  cto@acme.example  ", "ops@acme.example"]))

    assert delivery.cc_emails == ["cto@acme.example", "ops@acme.example"]
    assert Repo.get!(Delivery, delivery.id).cc_emails == ["cto@acme.example", "ops@acme.example"]
  end

  test "stores no CC addresses when none are given" do
    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(@attrs)

    assert Repo.get!(Delivery, delivery.id).cc_emails == []
  end

  test "drops repeated CC addresses, blank entries, and the recipient" do
    assert {:ok, %{delivery: delivery}} =
             DirectEmails.queue(
               Map.put(@attrs, "cc_emails", [
                 "cto@acme.example",
                 "CTO@acme.example",
                 "Recipient@Example.com",
                 " ",
                 "ops@acme.example"
               ])
             )

    assert delivery.cc_emails == ["cto@acme.example", "ops@acme.example"]
  end

  test "rejects a malformed CC address" do
    assert {:error, {:invalid, "cc_emails", "contains an invalid email address: not-an-address"}} =
             DirectEmails.queue(Map.put(@attrs, "cc_emails", ["cto@acme.example", "not-an-address"]))

    assert Repo.aggregate(from(d in Delivery, where: d.kind == "direct"), :count) == 0
  end

  test "rejects CC addresses that are not a list of strings" do
    assert {:error, {:invalid, "cc_emails", "must be a list of email addresses"}} =
             DirectEmails.queue(Map.put(@attrs, "cc_emails", "cto@acme.example"))

    assert {:error, {:invalid, "cc_emails", "must be a list of email addresses"}} =
             DirectEmails.queue(Map.put(@attrs, "cc_emails", [42]))
  end

  test "treats a changed CC list as a new send rather than a duplicate" do
    with_cc = Map.put(@attrs, "cc_emails", ["cto@acme.example"])

    assert {:ok, first} = DirectEmails.queue(with_cc)
    assert {:ok, added} = DirectEmails.queue(Map.put(@attrs, "cc_emails", ["cto@acme.example", "ops@acme.example"]))
    assert {:ok, removed} = DirectEmails.queue(@attrs)

    refute added.duplicate
    refute removed.duplicate
    assert Enum.uniq([first.delivery.id, added.delivery.id, removed.delivery.id]) |> length() == 3
  end

  test "treats the same CC addresses in another order as a duplicate" do
    assert {:ok, first} = DirectEmails.queue(Map.put(@attrs, "cc_emails", ["cto@acme.example", "ops@acme.example"]))
    assert {:ok, second} = DirectEmails.queue(Map.put(@attrs, "cc_emails", ["OPS@acme.example", "cto@acme.example"]))

    assert second.duplicate
    assert second.delivery.id == first.delivery.id
  end

  test "audits the CC addresses of a queued notice" do
    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(Map.put(@attrs, "cc_emails", ["cto@acme.example"]))

    activity = Repo.get_by!(Activity, action: "gtm_direct_email.queued", target_id: delivery.id)

    assert activity.metadata["cc_emails"] == ["cto@acme.example"]
  end

  test "rejects a missing or malformed recipient" do
    assert {:error, {:invalid, "recipient_email", "is required"}} =
             DirectEmails.queue(Map.delete(@attrs, "recipient_email"))

    assert {:error, {:invalid, "recipient_email", "is not a valid email address"}} =
             DirectEmails.queue(Map.put(@attrs, "recipient_email", "not-an-address"))
  end

  test "rejects a missing subject or body" do
    assert {:error, {:invalid, "subject", "is required"}} = DirectEmails.queue(Map.put(@attrs, "subject", "   "))

    assert {:error, {:invalid, "body_markdown", "is required"}} =
             DirectEmails.queue(Map.delete(@attrs, "body_markdown"))
  end

  test "rejects a malformed sender or reply-to" do
    assert {:error, {:invalid, "from_email", "is not a valid email address"}} =
             DirectEmails.queue(Map.put(@attrs, "from_email", "tuist.dev"))

    assert {:error, {:invalid, "reply_to_email", "is not a valid email address"}} =
             DirectEmails.queue(Map.put(@attrs, "reply_to_email", "marek at tuist.dev"))
  end

  test "get_delivery/1 ignores deliveries of another kind" do
    transactional =
      %Delivery{}
      |> Delivery.changeset(%{
        kind: "transactional",
        recipient_email: "recipient@example.com",
        subject: "Confirm your subscription",
        status: "pending"
      })
      |> Repo.insert!()

    refute DirectEmails.get_delivery(transactional.id)

    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(@attrs)
    assert DirectEmails.get_delivery(delivery.id).id == delivery.id
  end

  test "audits a queued notice with no account as null rather than the string nil" do
    assert {:ok, %{delivery: delivery}} = DirectEmails.queue(@attrs)

    activity = Repo.get_by!(Activity, action: "gtm_direct_email.queued", target_id: delivery.id)

    assert Map.fetch!(activity.metadata, "account_id") == nil
    assert Map.fetch!(activity.metadata, "account_key") == nil
    assert activity.metadata["subject"] == "Your Tuist pricing is changing"

    refute Map.has_key?(activity.metadata, "path")
    assert is_nil(Audit.serialize(activity).target.path)
  end
end
