defmodule Atlas.GTM.AudiencesTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.IncidentContact
  alias Atlas.Accounts.ServiceLevelExtractionCheck
  alias Atlas.Accounts.Term
  alias Atlas.Audit.Activity
  alias Atlas.Documents.Document
  alias Atlas.GTM.Audience
  alias Atlas.GTM.AudienceMembership
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.Subscriber
  alias Atlas.GTM.Workers.PostAudienceMemberNotification

  test "normalizes subscriber emails and paginates the result" do
    assert {:ok, subscriber} =
             Audiences.create_subscriber(%{
               email: "  Reader@Example.com ",
               first_name: "Reader",
               source: "website"
             })

    assert subscriber.email == "reader@example.com"

    assert {[listed], metadata} = Audiences.list_subscribers(page_size: 10)
    assert listed.id == subscriber.id
    assert metadata.total_count == 1

    assert Repo.get_by!(Activity, action: "gtm_subscriber.created").metadata["path"] == "/outbound/email"
  end

  test "adds a subscriber to an audience idempotently and tracks active counts" do
    audience = insert_audience!("Digest")
    subscriber = insert_subscriber!("digest@example.com")

    assert {:ok, membership} = Audiences.add_subscriber(audience, subscriber)
    assert membership.status == "subscribed"
    assert {:ok, repeated} = Audiences.add_subscriber(audience, subscriber)
    assert repeated.id == membership.id

    assert [job] = all_enqueued(worker: PostAudienceMemberNotification)
    assert job.args["membership_id"] == membership.id
    assert is_binary(job.args["notification_id"])

    {[listed], _meta} = Audiences.list_audiences(page_size: 100)
    assert listed.subscribers_count == 1

    assert {:ok, membership} = Audiences.unsubscribe(audience, subscriber)
    assert membership.status == "unsubscribed"
    refute Audiences.subscribed?(audience, subscriber)
  end

  test "announces a pending member only after the subscription is confirmed" do
    audience = insert_audience!("Email Digest")
    subscriber = insert_subscriber!("reader@example.com", "pending")

    assert {:ok, membership} = Audiences.add_subscriber(audience, subscriber, nil, "pending")
    refute_enqueued(worker: PostAudienceMemberNotification)

    assert {:ok, confirmed} = Audiences.add_subscriber(audience, subscriber)
    assert confirmed.id == membership.id
    assert_enqueued(worker: PostAudienceMemberNotification, args: %{"membership_id" => membership.id})

    assert {:ok, _repeated} = Audiences.add_subscriber(audience, subscriber)
    assert [_job] = all_enqueued(worker: PostAudienceMemberNotification)
  end

  test "returns only subscribers who are active globally and in the audience" do
    audience = insert_audience!("Announcements")
    active = insert_subscriber!("active@example.com")
    globally_unsubscribed = insert_subscriber!("global@example.com", "unsubscribed")
    audience_unsubscribed = insert_subscriber!("audience@example.com")

    for subscriber <- [active, globally_unsubscribed, audience_unsubscribed] do
      Audiences.add_subscriber(audience, subscriber)
    end

    Audiences.unsubscribe(audience, audience_unsubscribed)

    assert [recipient] = Audiences.subscribed_recipients(audience)
    assert recipient.id == active.id
  end

  test "resolves a dynamic audience from active customer account contacts" do
    matching_account = insert_account!("dynamic-matching", :customer)
    excluded_account = insert_account!("dynamic-excluded", :lead)
    matching_contact = insert_contact!(matching_account, unique_email("matching"))
    _excluded_contact = insert_contact!(excluded_account, unique_email("excluded"))

    assert {:ok, audience} =
             Audiences.create_audience(%{
               name: "Enterprise accounts",
               membership_type: "dynamic",
               rules: %{"account_segment" => "customer", "hosting" => "all"}
             })

    assert audience.membership_type == "dynamic"

    assert audience.rules == %{
             "account_segment" => "customer",
             "hosting" => "all",
             "recipient_source" => "account_contacts",
             "contacts_per_account" => "all"
           }

    {[membership], metadata} = Audiences.list_memberships(audience)
    assert membership.subscriber.email == matching_contact.email
    assert membership.subscriber.user_group == matching_account.name
    assert metadata.total_count == 1

    assert [recipient] = Audiences.subscribed_recipients(audience)
    assert recipient.email == matching_contact.email

    assert {:ok, _membership} = Audiences.unsubscribe(audience, recipient)
    assert Audiences.subscribed_recipients(audience) == []
  end

  test "uses an explicit account hosting setting before falling back to contract terms" do
    self_hosted_account = insert_account!("dynamic-self-hosted", :customer, hosting: "self_hosted")
    cloud_account = insert_account!("dynamic-cloud", :customer, hosting: "cloud")
    self_hosted_contact = insert_contact!(self_hosted_account, unique_email("on-premise"))
    _cloud_contact = insert_contact!(cloud_account, unique_email("cloud"))
    insert_term!(cloud_account, true)

    assert {:ok, audience} =
             Audiences.create_audience(%{
               name: "Self-hosted enterprise accounts",
               membership_type: "dynamic",
               rules: %{"account_segment" => "customer", "hosting" => "self_hosted"}
             })

    {[membership], metadata} = Audiences.list_memberships(audience)
    assert membership.subscriber.email == self_hosted_contact.email
    assert metadata.total_count == 1
  end

  test "resolves contract-derived incident contacts for a dynamic audience" do
    matching_account = insert_account!("dynamic-incident-matching", :customer)
    excluded_account = insert_account!("dynamic-incident-excluded", :lead)
    matching_contact = insert_incident_contact!(matching_account, unique_email("incident-matching"))
    _excluded_contact = insert_incident_contact!(excluded_account, unique_email("incident-excluded"))

    assert {:ok, audience} =
             Audiences.create_audience(%{
               name: "Enterprise security incident contacts",
               membership_type: "dynamic",
               rules: %{
                 "account_segment" => "customer",
                 "hosting" => "all",
                 "recipient_source" => "incident_contacts"
               }
             })

    {[membership], metadata} = Audiences.list_memberships(audience)
    assert membership.subscriber.email == matching_contact.email
    assert membership.subscriber.source == "contract"
    assert membership.subscriber.user_group == matching_account.name
    assert metadata.total_count == 1

    assert [recipient] = Audiences.subscribed_recipients(audience)
    assert recipient.email == matching_contact.email
    assert recipient.source == "contract"
  end

  test "uses one deterministic account contact when an audience limits contacts per account" do
    account = insert_account!("single-recipient", :customer)
    selected_contact = insert_contact!(account, unique_email("alpha"))
    _other_contact = insert_contact!(account, unique_email("zulu"))

    assert {:ok, audience} =
             Audiences.create_audience(%{
               name: "One recipient #{System.unique_integer([:positive])}",
               membership_type: "dynamic",
               rules: %{
                 "account_segment" => "customer",
                 "hosting" => "all",
                 "recipient_source" => "account_contacts",
                 "contacts_per_account" => "one"
               }
             })

    {[membership], metadata} = Audiences.list_memberships(audience)

    assert membership.subscriber.email == selected_contact.email
    assert metadata.total_count == 1
    assert [recipient] = Audiences.subscribed_recipients(audience)
    assert recipient.email == selected_contact.email
  end

  test "deletes an unused manual audience and its memberships" do
    audience = insert_audience!("Disposable #{System.unique_integer([:positive])}")
    subscriber = insert_subscriber!(unique_email("disposable"))
    assert {:ok, membership} = Audiences.add_subscriber(audience, subscriber)

    assert {:ok, deleted} = Audiences.delete_audience(audience)
    assert deleted.id == audience.id
    refute Audiences.get_audience(audience.id)
    refute Repo.get(AudienceMembership, membership.id)

    activity = Repo.get_by!(Activity, action: "gtm_audience.deleted")
    assert activity.metadata["dashboard_path"] == "/outbound/email"
  end

  test "retains dynamic audiences when deletion is requested" do
    assert {:ok, audience} =
             Audiences.create_audience(%{
               name: "Dynamic #{System.unique_integer([:positive])}",
               membership_type: "dynamic"
             })

    assert {:error, :dynamic_audience} = Audiences.delete_audience(audience)
    assert Audiences.get_audience(audience.id)
  end

  test "rejects an unknown dynamic audience rule" do
    assert {:error, changeset} =
             Audiences.create_audience(%{
               name: "Invalid dynamic audience",
               membership_type: "dynamic",
               rules: %{"account_segment" => "customer", "hosting" => "unknown"}
             })

    assert {:rules, {"has an invalid hosting filter", _opts}} =
             List.keyfind(changeset.errors, :rules, 0)
  end

  defp insert_audience!(name) do
    %Audience{}
    |> Audience.changeset(%{name: name, slug: String.downcase(name)})
    |> Repo.insert!()
  end

  defp insert_subscriber!(email, status \\ "subscribed") do
    %Subscriber{}
    |> Subscriber.changeset(%{email: email, source: "test", status: status})
    |> Repo.insert!()
  end

  defp insert_account!(key, segment, attrs \\ []) do
    %Account{}
    |> Account.changeset(
      %{
        account_key: "dynamic-audience-#{key}-#{System.unique_integer([:positive])}",
        name: "#{key} account",
        segment: segment,
        status: "active"
      }
      |> Map.merge(Map.new(attrs))
    )
    |> Repo.insert!()
  end

  defp insert_contact!(account, email) do
    %Contact{account_id: account.id}
    |> Contact.changeset(%{full_name: "#{account.name} contact", email: email})
    |> Repo.insert!()
  end

  defp insert_term!(account, on_premise) do
    %Term{account_id: account.id}
    |> Term.changeset(%{
      source: "test",
      payment: "yearly",
      start_date: Date.add(Date.utc_today(), -1),
      end_date: Date.add(Date.utc_today(), 1),
      total: 100,
      on_premise: on_premise
    })
    |> Repo.insert!()
  end

  defp insert_incident_contact!(account, email) do
    document =
      %Document{}
      |> Document.changeset(%{
        title: "Incident contacts",
        original_filename: "incident-contacts-#{System.unique_integer([:positive])}.txt",
        content_type: "text/plain",
        byte_size: 10,
        checksum_sha256: "#{System.unique_integer([:positive])}",
        storage_bucket: "test-documents",
        storage_key: "documents/#{System.unique_integer([:positive])}.txt",
        status: "ready",
        source: "upload"
      })
      |> Ecto.Changeset.change(account_id: account.id)
      |> Repo.insert!()

    check =
      %ServiceLevelExtractionCheck{account_id: account.id, document_id: document.id}
      |> ServiceLevelExtractionCheck.changeset(%{
        agent_version: "service_level_extraction_agent:v2",
        document_checksum_sha256: document.checksum_sha256,
        status: "completed"
      })
      |> Repo.insert!()

    %IncidentContact{
      account_id: account.id,
      document_id: document.id,
      service_level_extraction_check_id: check.id
    }
    |> IncidentContact.changeset(%{
      email: email,
      role: "Security incident notifications",
      source_page: 1,
      confidence: "0.95"
    })
    |> Repo.insert!()
  end

  defp unique_email(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}@example.com"
  end

  test "derives a slug that strips diacritics instead of splitting on them" do
    assert {:ok, audience} = Audiences.create_audience(%{name: "Señor Digest"})
    assert audience.slug == "senor-digest"
  end
end
