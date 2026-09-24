defmodule Atlas.GTM.TransactionalTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Swoosh.TestAssertions

  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Transactional
  alias Atlas.GTM.Workers.DeliverAutomatedEmail
  alias Atlas.UUIDv7

  # The id the Tuist marketing site passes today, from Tuist.Loops.
  @loops_template_id "cmfglb1pe5esq2w0ixnkdou94"
  @verification_url "https://tuist.dev/newsletter/verify?token=abc123"

  setup :verify_on_exit!

  test "queues the newsletter confirmation addressed by its Atlas name" do
    assert {:ok, result} =
             Transactional.send("newsletter-confirmation", "reader@example.com", %{
               "verificationUrl" => @verification_url
             })

    refute result.duplicate
    delivery = result.delivery
    assert delivery.kind == "transactional"
    assert delivery.recipient_email == "reader@example.com"
    assert delivery.metadata["template"] == "newsletter-confirmation"
    assert delivery.metadata["data_variables"]["verificationUrl"] == @verification_url

    assert_enqueued(worker: DeliverAutomatedEmail, args: %{"delivery_id" => delivery.id})
  end

  test "accepts the Loops template id so the caller only changes URL and key" do
    assert {:ok, result} =
             Transactional.send(@loops_template_id, "reader@example.com", %{
               "verificationUrl" => @verification_url
             })

    assert result.delivery.metadata["template"] == "newsletter-confirmation"
  end

  test "returns the queued delivery instead of sending twice on a retry" do
    variables = %{"verificationUrl" => @verification_url}

    assert {:ok, first} = Transactional.send(@loops_template_id, "reader@example.com", variables)
    assert {:ok, second} = Transactional.send(@loops_template_id, "reader@example.com", variables)

    assert second.duplicate
    assert second.delivery.id == first.delivery.id
    assert Repo.aggregate(from(d in Delivery, where: d.kind == "transactional"), :count) == 1
  end

  test "retries a primary-key collision with a fresh delivery id" do
    colliding_id = Ecto.UUID.generate()
    replacement_id = Ecto.UUID.generate()
    audit_id = Ecto.UUID.generate()

    %Delivery{id: colliding_id}
    |> Delivery.changeset(%{
      kind: "confirmation",
      recipient_email: "existing-delivery@example.com",
      subject: "Existing delivery",
      status: "pending"
    })
    |> Repo.insert!()

    # The successful send also records an audit event, which has its own
    # generated primary key after the delivery retry succeeds.
    Process.put(:transactional_delivery_ids, [colliding_id, replacement_id, audit_id])

    stub(UUIDv7, :autogenerate, fn ->
      [id | remaining_ids] = Process.get(:transactional_delivery_ids)
      Process.put(:transactional_delivery_ids, remaining_ids)
      id
    end)

    assert {:ok, %{delivery: delivery, duplicate: false}} =
             Transactional.send(@loops_template_id, "reader@example.com", %{
               "verificationUrl" => @verification_url
             })

    assert delivery.id == replacement_id
    assert Repo.get!(Delivery, replacement_id).recipient_email == "reader@example.com"
  end

  test "still dedupes when another transactional send to the same address lands in between" do
    variables = %{"verificationUrl" => @verification_url}

    assert {:ok, first} = Transactional.send(@loops_template_id, "reader@example.com", variables)

    assert {:ok, _other} =
             Transactional.send(@loops_template_id, "reader@example.com", %{
               "verificationUrl" => "https://tuist.dev/newsletter/verify?token=other"
             })

    assert {:ok, retry} = Transactional.send(@loops_template_id, "reader@example.com", variables)

    assert retry.duplicate
    assert retry.delivery.id == first.delivery.id
  end

  test "sends again when the verification link differs" do
    assert {:ok, first} =
             Transactional.send(@loops_template_id, "reader@example.com", %{"verificationUrl" => @verification_url})

    assert {:ok, second} =
             Transactional.send(@loops_template_id, "reader@example.com", %{
               "verificationUrl" => "https://tuist.dev/newsletter/verify?token=different"
             })

    refute second.duplicate
    assert second.delivery.id != first.delivery.id
  end

  test "rejects an unknown template" do
    assert {:error, :unknown_transactional_id} =
             Transactional.send("not-a-template", "reader@example.com", %{"verificationUrl" => @verification_url})
  end

  test "rejects a missing verification url" do
    assert {:error, {:missing_variables, ["verificationUrl"]}} =
             Transactional.send(@loops_template_id, "reader@example.com", %{})

    assert {:error, {:missing_variables, ["verificationUrl"]}} =
             Transactional.send(@loops_template_id, "reader@example.com", %{"verificationUrl" => "  "})
  end

  test "rejects a missing email" do
    assert {:error, :email_missing} =
             Transactional.send(@loops_template_id, "", %{"verificationUrl" => @verification_url})

    assert {:error, :email_missing} =
             Transactional.send(@loops_template_id, nil, %{"verificationUrl" => @verification_url})
  end

  test "the worker renders the verification link into the email" do
    assert {:ok, %{delivery: delivery}} =
             Transactional.send(@loops_template_id, "reader@example.com", %{
               "verificationUrl" => @verification_url
             })

    assert :ok = perform_job(DeliverAutomatedEmail, %{"delivery_id" => delivery.id})

    assert_email_sent(fn email ->
      assert email.to == [{"", "reader@example.com"}]
      assert email.subject == "Confirm your Tuist newsletter subscription"
      assert email.html_body =~ @verification_url
      assert email.text_body =~ @verification_url
    end)

    assert Repo.get!(Delivery, delivery.id).status == "delivered"
  end
end
