defmodule Atlas.Outreach do
  @moduledoc """
  LinkedIn outreach built on account contacts and account timeline events.
  """

  import Atlas.Outreach.Util, only: [normalize_optional_text: 1, present?: 1, attr: 3]
  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.GTM
  alias Atlas.GTM.OpportunityContact
  alias Atlas.GTM.Outreach.Apollo
  alias Atlas.GTM.Outreach.SearchSegments
  alias Atlas.Outreach.Candidate
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.MessageAttempts
  alias Atlas.Outreach.Recommendation
  alias Atlas.Outreach.Recommendations
  alias Atlas.Repo
  alias Atlas.Search
  alias Atlas.Users.User

  require Logger

  @event_kinds ~w(connection_requested connection_accepted message_sent message_received note)

  def event_kinds, do: @event_kinds
  def response_outcomes, do: MessageAttempt.response_outcomes()

  defdelegate list_recommendations(contact_or_id, opts \\ []), to: Recommendations, as: :list
  defdelegate get_recommendation(id), to: Recommendations, as: :get
  defdelegate current_recommendation(contact_or_id), to: Recommendations, as: :current
  defdelegate generate_recommendation(contact_id), to: Recommendations, as: :generate

  defdelegate request_recommendation_generation(contact_or_id, actor \\ nil, source \\ "dashboard"),
    to: Recommendations,
    as: :request_generation

  defdelegate recommendation_generation_pending?(contact_or_id),
    to: Recommendations,
    as: :generation_pending?

  defdelegate recommendation_generation_status(contact_or_id),
    to: Recommendations,
    as: :generation_status

  defdelegate complete_recommendation(recommendation_or_id, actor \\ nil, attrs \\ %{}),
    to: Recommendations,
    as: :complete

  defdelegate dismiss_recommendation(recommendation_or_id, reason \\ nil, actor \\ nil),
    to: Recommendations,
    as: :dismiss

  defdelegate regenerate_recommendation(recommendation_or_id, actor \\ nil, source \\ "manual"),
    to: Recommendations,
    as: :regenerate

  defdelegate enqueue_recommendation_generation(contact_id, source \\ "system", opts \\ []),
    to: Recommendations,
    as: :enqueue_generation

  defdelegate list_recommendation_candidate_ids(opts \\ []), to: Recommendations, as: :list_candidate_ids
  defdelegate mark_recommendation_notified(recommendation, attrs), to: Recommendations, as: :mark_notified

  defdelegate handle_recommendation_slack_action(action, recommendation_id, opts \\ []),
    to: Recommendations,
    as: :handle_slack_action

  def list_contacts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    status = Keyword.get(opts, :status)
    query = Keyword.get(opts, :query)
    sort_by = Keyword.get(opts, :sort_by)
    sort_order = Keyword.get(opts, :sort_order, "desc")

    contacts_query =
      Contact
      |> join(:inner, [contact], account in assoc(contact, :account))
      |> where([contact, _account], not is_nil(contact.outreach_enrolled_at))
      |> maybe_filter_status(status)
      |> maybe_filter_query(query)
      |> order_contacts(sort_by, sort_order)
      |> preload([_contact, account], account: account)

    Flop.run(contacts_query, %Flop{limit: limit, offset: offset}, for: Contact)
  end

  def list_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)
    offset = Keyword.get(opts, :offset, 0)
    page = Keyword.get(opts, :page)
    page_size = Keyword.get(opts, :page_size)
    status = Keyword.get(opts, :status)
    search_segment = Keyword.get(opts, :search_segment)
    query = Keyword.get(opts, :query)

    flop =
      if page || page_size do
        %Flop{page: max(page || 1, 1), page_size: max(page_size || 25, 1)}
      else
        %Flop{limit: limit, offset: offset}
      end

    candidates_query =
      Candidate
      |> maybe_filter_candidate(:status, status)
      |> maybe_filter_candidate(:search_segment, search_segment)
      |> maybe_filter_candidate_query(query)
      |> order_by(
        [candidate],
        asc: candidate.search_rank,
        desc: candidate.discovered_at,
        asc: candidate.id
      )
      |> preload(:contact)

    Flop.run(candidates_query, flop, for: Candidate)
  end

  def get_candidate(id) when is_binary(id), do: Repo.get(Candidate, id) |> preload_candidate()
  def get_candidate(_id), do: nil

  def list_candidates_pending_notification do
    Candidate
    |> where(
      [candidate],
      candidate.status == "pending" and not is_nil(candidate.slack_notification_requested_at) and
        is_nil(candidate.slack_notification_posted_at)
    )
    |> order_by([candidate], asc: candidate.slack_notification_requested_at, asc: candidate.id)
    |> Repo.all()
  end

  def mark_candidate_notified(%Candidate{} = candidate, attrs) when is_map(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    candidate
    |> Candidate.notification_changeset(%{
      slack_notification_posted_at: now,
      slack_notification_channel_id: attr(attrs, "channel_id", :channel_id),
      slack_notification_thread_ts: attr(attrs, "thread_ts", :thread_ts)
    })
    |> Repo.update()
    |> tap(fn
      {:ok, notified} -> audit_candidate_notification(notified)
      _result -> :ok
    end)
  end

  def search_apollo(actor \\ nil, opts \\ []) do
    segment_ids = Keyword.get(opts, :segments, Enum.map(SearchSegments.all(), & &1.id))
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    initial = %{created: 0, updated: 0, excluded: 0, returned: 0, total_matches: 0, segments: []}

    segment_ids
    |> Enum.reduce_while({:ok, initial}, fn segment_id, {:ok, result} ->
      case Apollo.search_outreach_segment(segment_id, opts) do
        {:ok, segment_result} ->
          persisted = persist_candidate_results(segment_result, now)

          segment_summary = %{
            id: segment_result.segment.id,
            name: segment_result.segment.name,
            returned: length(segment_result.people),
            total_matches: segment_result.total,
            excluded: segment_result.excluded
          }

          updated_result =
            result
            |> Map.update!(:created, &(&1 + persisted.created))
            |> Map.update!(:updated, &(&1 + persisted.updated))
            |> Map.update!(:excluded, &(&1 + segment_result.excluded))
            |> Map.update!(:returned, &(&1 + length(segment_result.people)))
            |> Map.update!(:total_matches, &(&1 + segment_result.total))
            |> Map.update!(:segments, &(&1 ++ [segment_summary]))

          {:cont, {:ok, updated_result}}

        {:error, reason} ->
          {:halt, {:error, {segment_id, reason}}}
      end
    end)
    |> tap(fn
      {:ok, result} -> audit_apollo_search(result, actor)
      {:error, {segment_id, reason}} -> audit_apollo_search_failure(segment_id, reason, actor)
    end)
  end

  def enroll_candidate(candidate_or_id, actor \\ nil, opts \\ [])

  def enroll_candidate(%Candidate{status: "enrolled", contact_id: contact_id}, _actor, _opts)
      when is_binary(contact_id) do
    case get_contact(contact_id) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  def enroll_candidate(%Candidate{} = candidate, actor, opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, details} <- candidate_details(candidate, opts),
         {:ok, account} <- find_or_create_apollo_account(candidate_organization(candidate, details)),
         contact_attrs = candidate_contact_attrs(candidate, details, now),
         true <- valid_apollo_identity?(contact_attrs),
         {:ok, contact, event} <- persist_candidate_enrollment(candidate, account, contact_attrs, actor, now) do
      Search.index_account_event(event)
      audit_candidate_enrollment(candidate, contact, actor)
      request_recommendation_after_enrollment(contact, actor, "candidate_enrolled")
      {:ok, preload_contact(contact)}
    else
      false -> {:error, :contact_identity_required}
      {:error, reason} -> {:error, reason}
    end
  end

  def enroll_candidate(id, actor, opts) when is_binary(id) do
    case Repo.get(Candidate, id) do
      nil -> {:error, :not_found}
      candidate -> enroll_candidate(candidate, actor, opts)
    end
  end

  def reject_candidate(candidate_or_id, reason \\ nil, actor \\ nil)

  def reject_candidate(%Candidate{} = candidate, reason, actor) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    candidate
    |> Candidate.review_changeset(%{
      status: "rejected",
      rejection_reason: normalize_optional_text(reason),
      reviewed_at: now,
      contact_id: nil
    })
    |> Repo.update()
    |> tap(fn
      {:ok, rejected} -> audit_candidate_rejection(rejected, actor)
      _result -> :ok
    end)
  end

  def reject_candidate(id, reason, actor) when is_binary(id) do
    case Repo.get(Candidate, id) do
      nil -> {:error, :not_found}
      candidate -> reject_candidate(candidate, reason, actor)
    end
  end

  def get_contact(id) when is_binary(id) do
    Contact
    |> Repo.get(id)
    |> preload_contact()
  end

  def get_contact(_id), do: nil

  def enroll_opportunity_contact(contact_or_id, actor \\ nil)

  def enroll_opportunity_contact(%OpportunityContact{} = suggestion, actor) do
    suggestion = Repo.preload(suggestion, :opportunity)

    with {:ok, account, _opportunity} <- GTM.convert_gtm_opportunity(suggestion.opportunity),
         {:ok, contact, event} <- persist_enrollment(account, suggestion, actor) do
      Search.index_account_event(event)
      request_recommendation_after_enrollment(contact, actor, "contact_enrolled")
      {:ok, preload_contact(contact)}
    end
  end

  def enroll_opportunity_contact(id, actor) when is_binary(id) do
    case Repo.get(OpportunityContact, id) do
      nil -> {:error, :not_found}
      suggestion -> enroll_opportunity_contact(suggestion, actor)
    end
  end

  def record_event(contact_or_id, attrs, actor \\ nil)

  def record_event(%Contact{} = contact, attrs, actor) when is_map(attrs) do
    kind = attr(attrs, "kind", :kind)
    body = normalize_optional_text(attr(attrs, "body", :body))
    subject = normalize_optional_text(attr(attrs, "subject", :subject))
    occurred_at = normalize_occurred_at(attr(attrs, "occurred_at", :occurred_at))
    response_outcome = normalize_optional_text(attr(attrs, "response_outcome", :response_outcome))
    recommendation_id = normalize_optional_text(attr(attrs, "recommendation_id", :recommendation_id))

    changeset =
      %Event{account_id: contact.account_id, contact_id: contact.id, author_id: actor_id(actor)}
      |> Event.changeset(%{
        external_id: "outreach:#{Ecto.UUID.generate()}",
        source: event_source(kind),
        kind: kind,
        title: event_title(kind),
        body: body,
        occurred_at: occurred_at,
        metadata:
          %{
            "outreach_status" => status_after(kind, contact.outreach_status, response_outcome),
            "response_outcome" => response_outcome,
            "recommendation_id" => recommendation_id,
            "subject" => subject
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
      })
      |> validate_event(kind, body, response_outcome)

    Repo.transaction(fn ->
      with {:ok, event} <- Repo.insert(changeset),
           {:ok, updated_contact} <-
             update_contact_after_event(contact, kind, occurred_at, response_outcome),
           {:ok, message_attempt} <- MessageAttempts.track(updated_contact, event, attrs) do
        {updated_contact, event, message_attempt}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {updated_contact, event, _message_attempt}} ->
        Search.index_account_event(event)
        audit_event(event, updated_contact, actor)
        {:ok, event, preload_contact(updated_contact)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def record_event(id, attrs, actor) when is_binary(id) and is_map(attrs) do
    case Repo.get(Contact, id) do
      nil -> {:error, :not_found}
      contact -> record_event(contact, attrs, actor)
    end
  end

  def change_event(attrs \\ %{}) do
    %Event{}
    |> Event.changeset(%{
      "external_id" => "preview",
      "source" => "linkedin",
      "kind" => attr(attrs, "kind", :kind) || "connection_requested",
      "title" => "Preview",
      "body" => attr(attrs, "body", :body),
      "occurred_at" => DateTime.utc_now() |> DateTime.truncate(:second),
      "account_id" => Ecto.UUID.generate()
    })
  end

  defp persist_enrollment(%Account{} = account, %OpportunityContact{} = suggestion, actor) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    attrs = enrollment_attrs(suggestion, now)
    existing = find_existing_contact(account.id, attrs)
    attrs = merge_existing_contact_attrs(attrs, existing, now)

    Repo.transaction(fn ->
      contact_changeset = Contact.outreach_changeset(existing || %Contact{account_id: account.id}, attrs)

      with {:ok, contact} <- Repo.insert_or_update(contact_changeset),
           {:ok, event} <- insert_enrollment_event(contact, suggestion, actor, now) do
        refresh_contact_count(account.id)
        audit_enrollment(contact, suggestion, actor)
        {contact, event}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {contact, event}} -> {:ok, contact, event}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_candidate_results(segment_result, now) do
    segment_result.people
    |> Enum.with_index(1)
    |> Enum.reduce(%{created: 0, updated: 0}, fn {person, rank}, result ->
      attrs = candidate_attrs(person, segment_result, rank, now)
      existing = Repo.get_by(Candidate, source: "apollo", source_id: attrs.source_id)
      action = if existing, do: :updated, else: :created
      attrs = merge_candidate_attrs(attrs, existing)

      candidate = existing || %Candidate{slack_notification_requested_at: now}

      Candidate.changeset(candidate, attrs)
      |> Repo.insert_or_update()
      |> case do
        {:ok, _candidate} -> Map.update!(result, action, &(&1 + 1))
        {:error, _changeset} -> result
      end
    end)
  end

  defp candidate_attrs(person, segment_result, rank, now) do
    organization_metadata = person.metadata["organization_metadata"] || %{}

    %{
      source: "apollo",
      source_id: person.source_id,
      search_segment: segment_result.segment.id,
      search_version: segment_result.segment.version,
      status: "pending",
      full_name: person.full_name,
      title: person.title,
      organization_name: person.organization_name,
      organization_source_id: person.metadata["organization_id"],
      organization_domain: person.metadata["organization_domain"],
      linkedin_url: person.linkedin_url,
      email: person.email,
      search_rank: rank,
      discovered_at: now,
      metadata:
        person.metadata
        |> Map.delete("organization_metadata")
        |> Map.merge(%{
          "confidence" => person.confidence,
          "organization" => organization_metadata,
          "search_definition" => segment_result.definition,
          "search_segments" => [segment_result.segment.id]
        })
    }
  end

  defp merge_candidate_attrs(attrs, nil), do: attrs

  defp merge_candidate_attrs(attrs, %Candidate{} = candidate) do
    existing_segments = candidate.metadata["search_segments"] || [candidate.search_segment]
    new_segments = attrs.metadata["search_segments"] || []

    metadata =
      candidate.metadata
      |> Map.merge(attrs.metadata)
      |> Map.put("search_segments", Enum.uniq(existing_segments ++ new_segments))

    attrs
    |> Map.put(:status, candidate.status)
    |> Map.put(:discovered_at, candidate.discovered_at)
    |> Map.put(:reviewed_at, candidate.reviewed_at)
    |> Map.put(:rejection_reason, candidate.rejection_reason)
    |> Map.put(:contact_id, candidate.contact_id)
    |> Map.put(:metadata, metadata)
  end

  defp candidate_details(%Candidate{} = candidate, opts) do
    if present?(candidate.linkedin_url) or present?(candidate.email) do
      {:ok, candidate_as_contact(candidate)}
    else
      Apollo.enrich_person(candidate.source_id, opts)
    end
  end

  defp candidate_as_contact(candidate) do
    %{
      source: candidate.source,
      source_id: candidate.source_id,
      full_name: candidate.full_name,
      title: candidate.title,
      organization_name: candidate.organization_name,
      linkedin_url: candidate.linkedin_url,
      email: candidate.email,
      confidence: candidate.metadata["confidence"],
      metadata: candidate.metadata
    }
  end

  defp candidate_organization(candidate, details) do
    %{
      source_id: candidate.organization_source_id || details.metadata["organization_id"],
      name: candidate.organization_name || details.organization_name,
      domain: candidate.organization_domain || details.metadata["organization_domain"],
      metadata: candidate.metadata["organization"] || details.metadata["organization_metadata"] || %{}
    }
  end

  defp candidate_contact_attrs(candidate, details, now) do
    %{
      full_name: details.full_name || candidate.full_name || details.email || "Apollo contact",
      email: details.email || candidate.email,
      title: details.title || candidate.title,
      linkedin_url: details.linkedin_url || candidate.linkedin_url,
      source: "apollo",
      source_id: candidate.source_id,
      outreach_enrolled_at: now,
      metadata:
        candidate.metadata
        |> Map.merge(details.metadata || %{})
        |> Map.put("apollo_id", candidate.source_id)
        |> Map.put("outreach_candidate_id", candidate.id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp persist_candidate_enrollment(candidate, account, contact_attrs, actor, now) do
    existing = find_existing_contact(account.id, contact_attrs)
    contact_attrs = merge_existing_contact_attrs(contact_attrs, existing, now)

    Repo.transaction(fn ->
      changeset = Contact.outreach_changeset(existing || %Contact{account_id: account.id}, contact_attrs)

      with {:ok, contact} <- Repo.insert_or_update(changeset),
           {:ok, event} <- insert_candidate_enrollment_event(contact, candidate, actor, now),
           {:ok, _candidate} <-
             candidate
             |> Candidate.review_changeset(%{
               status: "enrolled",
               rejection_reason: nil,
               reviewed_at: now,
               contact_id: contact.id
             })
             |> Repo.update() do
        refresh_contact_count(account.id)
        {contact, event}
      else
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, {contact, event}} -> {:ok, contact, event}
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_apollo_identity?(attrs) do
    present?(Map.get(attrs, :source_id)) and
      (present?(Map.get(attrs, :email)) or present?(Map.get(attrs, :linkedin_url)))
  end

  defp find_or_create_apollo_account(organization) do
    domain = normalize_domain(organization.domain)
    name = organization.name |> to_string() |> String.trim()
    account_key = apollo_account_key(organization, domain, name)

    case find_account_by_domain(domain) || find_account_by_name(name) ||
           Repo.get_by(Account, account_key: account_key) do
      %Account{} = account ->
        {:ok, account}

      nil ->
        Accounts.create_account(%{
          account_key: account_key,
          name: name,
          primary_domain: domain,
          url: domain && "https://#{domain}",
          segment: :prospect,
          metadata: %{
            "created_from" => "apollo_outreach_search",
            "apollo_account_id" => organization.source_id
          }
        })
    end
  end

  defp find_account_by_domain(nil), do: nil

  defp find_account_by_domain(domain) do
    # `domain` is already normalized (no protocol/www), but stored
    # primary_domain values may carry a www. prefix, so match both forms.
    Account
    |> where([account], fragment("lower(?) IN (?, ?)", account.primary_domain, ^domain, ^("www." <> domain)))
    |> limit(1)
    |> Repo.one()
  end

  defp find_account_by_name(""), do: nil

  defp find_account_by_name(name) do
    Account
    |> where([account], fragment("lower(?) = ?", account.name, ^String.downcase(name)))
    |> limit(1)
    |> Repo.one()
  end

  defp apollo_account_key(organization, domain, name) do
    value = organization.source_id || domain || name
    "apollo:" <> slug(value)
  end

  defp insert_candidate_enrollment_event(contact, candidate, actor, occurred_at) do
    external_id = "outreach-candidate-enrollment:#{candidate.id}"

    case Repo.get_by(Event, source: "apollo", external_id: external_id) do
      nil ->
        %Event{account_id: contact.account_id, contact_id: contact.id, author_id: actor_id(actor)}
        |> Event.changeset(%{
          external_id: external_id,
          source: "apollo",
          kind: "enrolled",
          title: "Added to LinkedIn outreach",
          body: "Discovered through an Apollo search and added to the outreach queue.",
          occurred_at: occurred_at,
          url: contact.linkedin_url,
          metadata: %{
            "apollo_id" => candidate.source_id,
            "outreach_candidate_id" => candidate.id,
            "search_segment" => candidate.search_segment
          }
        })
        |> Repo.insert()

      event ->
        {:ok, event}
    end
  end

  defp enrollment_attrs(suggestion, now) do
    %{
      full_name: suggestion.full_name || suggestion.email || "LinkedIn contact",
      email: suggestion.email,
      title: suggestion.title,
      source: suggestion.source || "apollo",
      source_id: suggestion.metadata["apollo_id"],
      linkedin_url: suggestion.linkedin_url,
      outreach_enrolled_at: now,
      metadata: suggestion.metadata || %{}
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp merge_existing_contact_attrs(attrs, nil, _now), do: attrs

  defp merge_existing_contact_attrs(attrs, %Contact{} = contact, now) do
    attrs
    |> Map.put(:outreach_enrolled_at, contact.outreach_enrolled_at || now)
    |> Map.update(:metadata, contact.metadata || %{}, &Map.merge(contact.metadata || %{}, &1))
  end

  defp find_existing_contact(account_id, attrs) do
    find_contact_by_source(account_id, Map.get(attrs, :source), Map.get(attrs, :source_id)) ||
      find_contact_by_linkedin(account_id, Map.get(attrs, :linkedin_url)) ||
      find_contact_by_email(account_id, Map.get(attrs, :email))
  end

  defp find_contact_by_source(account_id, source, source_id) when is_binary(source_id) and source_id != "" do
    Repo.get_by(Contact, account_id: account_id, source: source, source_id: source_id)
  end

  defp find_contact_by_source(_account_id, _source, _source_id), do: nil

  defp find_contact_by_linkedin(account_id, linkedin_url) when is_binary(linkedin_url) and linkedin_url != "" do
    Repo.get_by(Contact, account_id: account_id, linkedin_url: linkedin_url)
  end

  defp find_contact_by_linkedin(_account_id, _linkedin_url), do: nil

  defp find_contact_by_email(account_id, email) when is_binary(email) and email != "" do
    Repo.get_by(Contact, account_id: account_id, email: email)
  end

  defp find_contact_by_email(_account_id, _email), do: nil

  defp insert_enrollment_event(contact, suggestion, actor, occurred_at) do
    source = suggestion.source || "apollo"
    external_id = "outreach-enrollment:#{suggestion.id}"

    case Repo.get_by(Event, source: source, external_id: external_id) do
      nil ->
        %Event{account_id: contact.account_id, contact_id: contact.id, author_id: actor_id(actor)}
        |> Event.changeset(%{
          external_id: external_id,
          source: source,
          kind: "enrolled",
          title: "Added to LinkedIn outreach",
          body: "Discovered through Apollo and added to the outreach queue.",
          occurred_at: occurred_at,
          url: suggestion.linkedin_url,
          metadata: %{"opportunity_contact_id" => suggestion.id, "opportunity_id" => suggestion.opportunity_id}
        })
        |> Repo.insert()

      event ->
        {:ok, event}
    end
  end

  defp update_contact_after_event(contact, kind, occurred_at, response_outcome) do
    outreach_status = status_after(kind, contact.outreach_status, response_outcome)

    attrs =
      %{
        outreach_status: outreach_status,
        outreach_enrolled_at: contact.outreach_enrolled_at || occurred_at
      }
      |> maybe_put_last_outreach_at(kind, occurred_at)

    contact
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  # last_outreach_at tracks the last time WE reached out, so inbound-only
  # events (their reply) and notes must not advance it.
  defp maybe_put_last_outreach_at(attrs, "note", _occurred_at), do: attrs
  defp maybe_put_last_outreach_at(attrs, "message_received", _occurred_at), do: attrs
  defp maybe_put_last_outreach_at(attrs, _kind, occurred_at), do: Map.put(attrs, :last_outreach_at, occurred_at)

  defp validate_event(changeset, kind, body, response_outcome) do
    changeset =
      if kind in @event_kinds do
        changeset
      else
        Ecto.Changeset.add_error(changeset, :kind, "is not supported")
      end

    changeset =
      if kind in ~w(message_sent message_received note) and is_nil(body) do
        Ecto.Changeset.add_error(changeset, :body, "can't be blank")
      else
        changeset
      end

    if is_nil(response_outcome) or
         (kind == "message_received" and response_outcome in MessageAttempt.response_outcomes()) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :metadata, "has an unsupported response outcome")
    end
  end

  # Events can be recorded out of order, so the pipeline stage only moves
  # forward: an earlier-stage event never regresses a more advanced contact.
  defp status_after(kind, current, response_outcome)

  defp status_after(_kind, "not_interested", _response_outcome), do: "not_interested"
  defp status_after("message_received", _current, "positive_reply"), do: "interested"
  defp status_after("message_received", _current, "not_interested"), do: "not_interested"

  defp status_after(kind, current, _response_outcome) do
    candidate = stage_for_kind(kind, current)

    if stage_rank(candidate) >= stage_rank(current), do: candidate, else: current
  end

  defp stage_for_kind("connection_requested", _current), do: "connection_requested"
  defp stage_for_kind("connection_accepted", _current), do: "connected"
  defp stage_for_kind("message_sent", _current), do: "conversation_started"
  defp stage_for_kind("message_received", _current), do: "replied"
  defp stage_for_kind("note", current), do: current
  defp stage_for_kind(_kind, current), do: current

  defp stage_rank("connection_requested"), do: 1
  defp stage_rank("connected"), do: 2
  defp stage_rank("conversation_started"), do: 3
  defp stage_rank("replied"), do: 4
  defp stage_rank("interested"), do: 5
  defp stage_rank("not_interested"), do: 6
  defp stage_rank(_stage), do: 0

  defp event_source("note"), do: "atlas"
  defp event_source(_kind), do: "linkedin"

  defp event_title("connection_requested"), do: "Connection request sent"
  defp event_title("connection_accepted"), do: "Connection accepted"
  defp event_title("message_sent"), do: "Message sent"
  defp event_title("message_received"), do: "Message received"
  defp event_title("note"), do: "Outreach note"
  defp event_title(_kind), do: "Outreach activity"

  defp normalize_occurred_at(%DateTime{} = occurred_at), do: DateTime.truncate(occurred_at, :second)

  defp normalize_occurred_at(occurred_at) when is_binary(occurred_at) do
    case DateTime.from_iso8601(occurred_at) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  defp normalize_occurred_at(_occurred_at), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp preload_contact(nil), do: nil

  defp preload_contact(%Contact{} = contact) do
    Repo.preload(
      contact,
      [
        :account,
        events:
          from(event in Event,
            order_by: [desc: event.occurred_at, desc: event.inserted_at],
            preload: [:author]
          ),
        outreach_recommendations:
          from(recommendation in Recommendation,
            order_by: [desc: recommendation.inserted_at],
            preload: [:reviewed_by, :source_event]
          )
      ],
      force: true
    )
  end

  defp audit_enrollment(contact, suggestion, actor) do
    Audit.record(
      "outreach.contact_enrolled",
      %{
        target_type: "contact",
        target_id: contact.id,
        target_label: contact.full_name,
        metadata: %{
          "account_id" => contact.account_id,
          "opportunity_id" => suggestion.opportunity_id,
          "source" => contact.source,
          "path" => "/commercial/gtm/outreach/#{contact.id}"
        }
      },
      actor: actor
    )
  end

  defp audit_event(event, contact, actor) do
    Audit.record(
      "outreach.event_recorded",
      %{
        target_type: "contact_outreach_event",
        target_id: event.id,
        target_label: event.title,
        metadata:
          Map.merge(
            %{
              "account_id" => contact.account_id,
              "contact_id" => contact.id,
              "kind" => event.kind,
              "path" => "/commercial/gtm/outreach/#{contact.id}"
            },
            Map.take(event.metadata || %{}, ["recommendation_id", "response_outcome", "subject"])
          )
      },
      actor: actor
    )
  end

  defp audit_candidate_enrollment(candidate, contact, actor) do
    Audit.record(
      "outreach.candidate_enrolled",
      %{
        target_type: "contact",
        target_id: contact.id,
        target_label: contact.full_name,
        metadata: %{
          "account_id" => contact.account_id,
          "candidate_id" => candidate.id,
          "search_segment" => candidate.search_segment,
          "source" => "apollo",
          "path" => "/commercial/gtm/outreach/#{contact.id}"
        }
      },
      actor: actor
    )
  end

  defp audit_candidate_rejection(candidate, actor) do
    Audit.record(
      "outreach.candidate_rejected",
      %{
        target_type: "outreach_candidate",
        target_id: candidate.id,
        target_label: candidate.full_name || candidate.title || "Apollo candidate",
        metadata: %{
          "reason" => candidate.rejection_reason,
          "search_segment" => candidate.search_segment,
          "path" => "/commercial/gtm/outreach"
        }
      },
      actor: actor
    )
  end

  defp audit_candidate_notification(candidate) do
    Audit.record(
      "outreach.candidate_notified",
      %{
        target_type: "outreach_candidate",
        target_id: candidate.id,
        target_label: candidate.full_name || candidate.title || "Outreach candidate",
        metadata: %{
          "slack_channel_id" => candidate.slack_notification_channel_id,
          "slack_thread_ts" => candidate.slack_notification_thread_ts,
          "search_segment" => candidate.search_segment,
          "path" => "/commercial/gtm/outreach"
        }
      }
    )
  end

  defp request_recommendation_after_enrollment(contact, actor, source) do
    case request_recommendation_generation(contact, actor, source) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Could not enqueue an outreach recommendation after enrollment for contact #{contact.id}: #{inspect(reason)}"
        )
    end
  end

  defp audit_apollo_search(result, actor) do
    Audit.record(
      "outreach.apollo_searched",
      %{
        target_type: "outreach_search",
        target_id: "apollo-outreach-search",
        target_label: "Apollo outreach search",
        metadata: %{
          "created" => result.created,
          "updated" => result.updated,
          "excluded" => result.excluded,
          "returned" => result.returned,
          "total_matches" => result.total_matches,
          "segments" => result.segments,
          "path" => "/commercial/gtm/outreach"
        }
      },
      actor: actor
    )
  end

  defp audit_apollo_search_failure(segment_id, reason, actor) do
    Audit.record(
      "outreach.apollo_search_failed",
      %{
        target_type: "outreach_search",
        target_id: segment_id,
        target_label: "Apollo outreach search",
        metadata: %{
          "reason" => inspect(reason),
          "path" => "/commercial/gtm/outreach"
        }
      },
      actor: actor
    )
  end

  defp refresh_contact_count(account_id) do
    count = Repo.aggregate(from(contact in Contact, where: contact.account_id == ^account_id), :count)

    Account
    |> where([account], account.id == ^account_id)
    |> Repo.update_all(set: [contacts_count: count])
  end

  defp actor_id(%User{id: id}), do: id
  defp actor_id(_actor), do: nil

  defp preload_candidate(nil), do: nil
  defp preload_candidate(%Candidate{} = candidate), do: Repo.preload(candidate, :contact)

  defp maybe_filter_candidate(query, _field, nil), do: query
  defp maybe_filter_candidate(query, _field, ""), do: query
  defp maybe_filter_candidate(query, field, value), do: where(query, [candidate], field(candidate, ^field) == ^value)

  defp maybe_filter_candidate_query(query, nil), do: query
  defp maybe_filter_candidate_query(query, ""), do: query

  defp maybe_filter_candidate_query(query, value) do
    pattern = "%#{String.trim(value)}%"

    where(
      query,
      [candidate],
      ilike(candidate.full_name, ^pattern) or ilike(candidate.title, ^pattern) or
        ilike(candidate.organization_name, ^pattern)
    )
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [contact, _account], contact.outreach_status == ^status)

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query

  defp maybe_filter_query(query, value) do
    pattern = "%#{String.trim(value)}%"

    where(
      query,
      [contact, account],
      ilike(contact.full_name, ^pattern) or ilike(contact.title, ^pattern) or ilike(account.name, ^pattern)
    )
  end

  defp order_contacts(query, "full_name", "asc"), do: order_by(query, [contact, _account], asc: contact.full_name)

  defp order_contacts(query, "full_name", _order), do: order_by(query, [contact, _account], desc: contact.full_name)

  defp order_contacts(query, "last_outreach_at", "asc") do
    order_by(query, [contact, _account], asc_nulls_first: contact.last_outreach_at, asc: contact.full_name)
  end

  defp order_contacts(query, "last_outreach_at", _order) do
    order_by(query, [contact, _account], desc_nulls_last: contact.last_outreach_at, asc: contact.full_name)
  end

  defp order_contacts(query, "outreach_enrolled_at", "asc") do
    order_by(query, [contact, _account], asc: contact.outreach_enrolled_at, asc: contact.full_name)
  end

  defp order_contacts(query, "outreach_enrolled_at", _order) do
    order_by(query, [contact, _account], desc: contact.outreach_enrolled_at, asc: contact.full_name)
  end

  defp order_contacts(query, _sort_by, _sort_order) do
    order_by(query, [contact, account],
      asc:
        fragment(
          "CASE ? WHEN 'replied' THEN 0 WHEN 'conversation_started' THEN 1 WHEN 'connected' THEN 2 WHEN 'connection_requested' THEN 3 WHEN 'not_contacted' THEN 4 ELSE 5 END",
          contact.outreach_status
        ),
      desc_nulls_last: contact.last_outreach_at,
      asc: account.name,
      asc: contact.full_name
    )
  end

  defp normalize_domain(nil), do: nil

  defp normalize_domain(domain) when is_binary(domain) do
    domain
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/^https?:\/\//, "")
    |> String.replace(~r/^www\./, "")
    |> String.split("/", parts: 2)
    |> List.first()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
