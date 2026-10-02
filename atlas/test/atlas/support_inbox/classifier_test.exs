defmodule Atlas.SupportInbox.ClassifierTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Inbox.InboxEmail
  alias Atlas.Repo
  alias Atlas.Support.Message
  alias Atlas.Support.Thread
  alias Atlas.SupportInbox.Classifier

  setup :verify_on_exit!

  describe "classify/3 — thread-continuity gate" do
    test "skips the classifier and pings when the thread has prior activity" do
      %{thread: thread, message: inbound} = fresh_thread_with_message("continue@customer.example")

      # A second inbound on the same thread — makes prior_activity_count > 0
      # without needing an author/delivery_status like outbound would.
      _prior = insert_inbound_message!(thread, "earlier body")

      classifier = fn _ -> flunk("classifier should not be called for a live conversation") end

      assert {:ok, decision} = Classifier.classify(thread, inbound, classifier: classifier)
      assert decision.source == :continuity
      assert decision.action_needed
      assert decision.category == :support
    end

    test "runs the classifier for a fresh single-message thread" do
      %{thread: thread, message: inbound} = fresh_thread_with_message("cold@customer.example")

      classifier = fn %{from: from, subject: subject} ->
        assert from == "cold@customer.example"
        assert is_binary(subject)

        {:ok,
         %{
           category: :support,
           action_needed: true,
           urgency: :normal,
           confidence: 0.9,
           reason: "Question about the product."
         }}
      end

      assert {:ok, decision} = Classifier.classify(thread, inbound, classifier: classifier)
      assert decision.source == :classifier
      refute decision.low_confidence?
    end
  end

  describe "classify/3 — low-confidence promotion" do
    test "promotes a would-be silent decision to an action-needed ping when confidence is low" do
      %{thread: thread, message: inbound} = fresh_thread_with_message("edge@vendor.example")

      classifier = fn _ ->
        {:ok,
         %{
           category: :vendor_notice,
           action_needed: false,
           urgency: :none,
           confidence: 0.4,
           reason: "Might be a payment problem."
         }}
      end

      assert {:ok, decision} = Classifier.classify(thread, inbound, classifier: classifier)

      assert decision.low_confidence?
      assert decision.action_needed
      assert decision.urgency == :normal
      assert decision.source == :classifier
    end

    test "does not promote a high-confidence silent decision" do
      %{thread: thread, message: inbound} = fresh_thread_with_message("shipping@vendor.example")

      classifier = fn _ ->
        {:ok,
         %{
           category: :shipping,
           action_needed: false,
           urgency: :none,
           confidence: 0.95,
           reason: "Routine tracking update."
         }}
      end

      assert {:ok, decision} = Classifier.classify(thread, inbound, classifier: classifier)

      refute decision.low_confidence?
      refute decision.action_needed
      assert decision.urgency == :none
    end
  end

  describe "classify/3 — classifier failure" do
    test "falls back to an action-needed ping when the classifier errors" do
      %{thread: thread, message: inbound} = fresh_thread_with_message("mystery@customer.example")

      classifier = fn _ -> {:error, :llm_not_configured} end

      assert {:ok, decision} = Classifier.classify(thread, inbound, classifier: classifier)

      assert decision.source == :fallback
      assert decision.action_needed
      assert decision.urgency == :normal
      assert decision.low_confidence?
    end
  end

  describe "classify_and_persist/3" do
    test "writes the decision onto the thread" do
      %{thread: thread, message: inbound} = fresh_thread_with_message("persist@customer.example")

      classifier = fn _ ->
        {:ok,
         %{
           category: :invoice,
           action_needed: false,
           urgency: :none,
           confidence: 0.99,
           reason: "Cloudflare invoice with matching transaction."
         }}
      end

      assert {:ok, _decision} = Classifier.classify_and_persist(thread, inbound, classifier: classifier)

      reloaded = Repo.get!(Thread, thread.id)
      assert reloaded.classification == "invoice"
      assert reloaded.action_needed == false
      assert reloaded.urgency == "none"
      assert reloaded.classifier_confidence == 0.99
      assert reloaded.classified_at
    end
  end

  defp fresh_thread_with_message(customer_email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    thread =
      %Thread{}
      |> Thread.inbound_changeset(%{
        customer_name: "Test Customer",
        customer_email: customer_email,
        subject: "Test inbound",
        status: "open",
        last_message_at: now,
        last_inbound_at: now
      })
      |> Repo.insert!()

    message = insert_inbound_message!(thread, "Hello, this is the inbound body.")

    %{thread: thread, message: message}
  end

  defp insert_inbound_message!(thread, body) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    inbox_email =
      InboxEmail.create_changeset(%{
        raw_email: "raw",
        envelope_from: thread.customer_email,
        envelope_to: "contact@tuist.dev",
        received_at: now
      })
      |> Repo.insert!()

    %Message{thread_id: thread.id}
    |> Message.inbound_changeset(%{
      inbox_email_id: inbox_email.id,
      kind: "inbound",
      message_id: "<#{Ecto.UUID.generate()}@customer.example>",
      sender_email: thread.customer_email,
      body: body,
      occurred_at: now
    })
    |> Repo.insert!()
  end
end
