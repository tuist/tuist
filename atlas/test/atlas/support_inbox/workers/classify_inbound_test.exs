defmodule Atlas.SupportInbox.Workers.ClassifyInboundTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Inbox
  alias Atlas.Inbox.EmailParser
  alias Atlas.Support
  alias Atlas.Support.Workers.PostNotification
  alias Atlas.SupportInbox.Agents.ClassifierAgent
  alias Atlas.SupportInbox.Classifier
  alias Atlas.SupportInbox.Workers.ClassifyInbound

  setup :verify_on_exit!

  setup do
    suffix = System.unique_integer([:positive])

    raw = """
    Message-ID: <publish-#{suffix}@vendor.example>
    From: Vendor <noreply@vendor.example>
    To: contact@tuist.dev
    Subject: Package published

    Your package was published.
    """

    {:ok, email} =
      Inbox.persist_inbound(raw, envelope: %{"from" => "noreply@vendor.example", "to" => "contact@tuist.dev"})

    {:ok, result} = Support.ingest_inbound(EmailParser.parse(raw), email.id)
    result
  end

  test "resolves routine mail before enqueueing its notification", %{thread: thread, message: message} do
    expect(ClassifierAgent, :classify, fn _ ->
      {:ok,
       %{
         category: :publish,
         action_needed: false,
         urgency: :none,
         confidence: 0.99,
         reason: "Routine publication confirmation."
       }}
    end)

    assert :ok = perform_job(ClassifyInbound, %{thread_id: thread.id, message_id: message.id})
    assert Support.get_thread(thread.id).status == "resolved"
    assert_enqueued(worker: PostNotification, args: %{thread_id: thread.id, message_id: message.id})
  end

  test "does not enqueue a notification when persistence fails", %{thread: thread, message: message} do
    expect(Classifier, :classify_and_persist, fn _, _ -> {:error, :persistence_failed} end)

    assert {:error, :persistence_failed} =
             perform_job(ClassifyInbound, %{thread_id: thread.id, message_id: message.id})

    refute_enqueued(worker: PostNotification)
  end

  test "rolls back classification and resolution when notification enqueue fails", %{thread: thread, message: message} do
    expect(ClassifierAgent, :classify, fn _ ->
      {:ok, %{category: :publish, action_needed: false, urgency: :none, confidence: 0.99, reason: "Package published."}}
    end)

    expect(Oban, :insert, fn _ -> {:error, :enqueue_failed} end)

    assert {:error, :enqueue_failed} =
             perform_job(ClassifyInbound, %{thread_id: thread.id, message_id: message.id})

    reloaded = Support.get_thread(thread.id)
    assert reloaded.status == "open"
    refute reloaded.classified_at
    refute reloaded.resolved_at
    refute_enqueued(worker: PostNotification)
  end

  test "retries reuse the persisted decision and a single notification job", %{thread: thread, message: message} do
    expect(ClassifierAgent, :classify, fn _ ->
      {:ok, %{category: :publish, action_needed: false, urgency: :none, confidence: 0.99, reason: "Package published."}}
    end)

    args = %{thread_id: thread.id, message_id: message.id}
    assert :ok = perform_job(ClassifyInbound, args)
    classified = Support.get_thread(thread.id)

    stub(ClassifierAgent, :classify, fn _ -> flunk("a retry must not ask the model for a different decision") end)
    assert :ok = perform_job(ClassifyInbound, args)
    reloaded = Support.get_thread(thread.id)
    assert reloaded.status == "resolved"
    refute reloaded.action_needed
    assert reloaded.classified_at == classified.classified_at
    assert reloaded.resolved_at == classified.resolved_at
    assert length(all_enqueued(worker: PostNotification)) == 1
  end
end
