defmodule Atlas.GTM do
  @moduledoc """
  Go-to-market context. Owns content-side artifacts such as blog post ideas
  and their follow-up conversations. Unlike sales artifacts, GTM ideas are
  company-wide and not scoped to a customer account.
  """

  import Ecto.Query

  alias Atlas.Accounts
  alias Atlas.Accounts.Account
  alias Atlas.Audit
  alias Atlas.GTM.Audiences
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.BlogPostIdeaComment
  alias Atlas.GTM.Broadcasts
  alias Atlas.GTM.ContactIngest
  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.OpportunityContact
  alias Atlas.GTM.Outreach.Apollo
  alias Atlas.GTM.Outreach.Scanner
  alias Atlas.GTM.Outreach.Scoring
  alias Atlas.GTM.Outreach.SlackNotifier
  alias Atlas.GTM.Outreach.Topics
  alias Atlas.GTM.Signal
  alias Atlas.GTM.SignalQuery
  alias Atlas.GTM.SocialChannelIdea
  alias Atlas.GTM.SocialPostRevision
  alias Atlas.GTM.Transactional
  alias Atlas.GTM.Workers.PostBlogPostIdeaAnnouncement
  alias Atlas.Repo
  alias Atlas.Search

  require Logger

  defdelegate list_email_subscribers(opts \\ []), to: Audiences, as: :list_subscribers
  defdelegate list_all_email_subscribers(), to: Audiences, as: :list_all_subscribers
  defdelegate get_email_subscriber(id), to: Audiences, as: :get_subscriber
  defdelegate get_email_subscriber_by_email(email), to: Audiences, as: :get_subscriber_by_email
  defdelegate change_email_subscriber(subscriber, attrs \\ %{}), to: Audiences, as: :change_subscriber
  defdelegate create_email_subscriber(attrs, actor \\ nil), to: Audiences, as: :create_subscriber
  defdelegate update_email_subscriber(subscriber, attrs, actor \\ nil), to: Audiences, as: :update_subscriber
  defdelegate list_email_audiences(opts \\ []), to: Audiences, as: :list_audiences
  defdelegate list_all_email_audiences(), to: Audiences, as: :list_all_audiences
  defdelegate distinct_email_audience_source_ids(), to: Audiences, as: :distinct_source_ids
  defdelegate email_audience_presence_values(), to: Audiences, as: :presence_values
  defdelegate distinct_email_subscriber_sources(), to: Audiences, as: :distinct_subscriber_sources
  defdelegate get_email_audience(id), to: Audiences, as: :get_audience
  defdelegate get_email_audience_by_slug(slug), to: Audiences, as: :get_audience_by_slug
  defdelegate get_email_audience_by_source_id(source_id), to: Audiences, as: :get_audience_by_source_id
  defdelegate get_email_audience_with_counts(id), to: Audiences, as: :get_audience_with_counts
  defdelegate list_email_audience_memberships(audience, opts \\ []), to: Audiences, as: :list_memberships
  defdelegate list_email_audience_broadcasts(audience, opts \\ []), to: Broadcasts, as: :list_broadcasts
  defdelegate upsert_email_contact(payload), to: ContactIngest, as: :upsert_contact

  defdelegate send_email_transactional(transactional_id, email, data_variables \\ %{}),
    to: Transactional,
    as: :send

  defdelegate change_email_audience(audience, attrs \\ %{}), to: Audiences, as: :change_audience
  defdelegate create_email_audience(attrs, actor \\ nil), to: Audiences, as: :create_audience
  defdelegate delete_email_audience(audience, actor \\ nil), to: Audiences, as: :delete_audience

  defdelegate add_email_audience_subscriber(audience, subscriber, actor \\ nil),
    to: Audiences,
    as: :add_subscriber

  defdelegate unsubscribe_email_audience_subscriber(audience, subscriber, actor \\ nil),
    to: Audiences,
    as: :unsubscribe

  defdelegate change_email_broadcast(audience, attrs \\ %{}, sender \\ nil),
    to: Broadcasts,
    as: :change_broadcast

  defdelegate queue_email_broadcast(audience, attrs, sender \\ nil),
    to: Broadcasts,
    as: :queue_broadcast

  @doc """
  Bearer token the Loops-compatible email endpoints expect. Nil until
  `ATLAS_GTM_INGEST_TOKEN` is configured, which keeps them closed by default.
  """
  def email_contact_ingest_token do
    :atlas |> Application.get_env(:gtm_ingest, []) |> Keyword.get(:token)
  end

  @doc """
  Lists blog post ideas, newest first, with their comments preloaded.
  """
  def list_blog_post_ideas do
    BlogPostIdea
    |> order_by([idea],
      asc:
        fragment(
          "CASE ? WHEN 'idea' THEN 0 WHEN 'in_progress' THEN 1 WHEN 'published' THEN 2 ELSE 3 END",
          idea.status
        ),
      desc: idea.inserted_at
    )
    |> preload([:author, :comments])
    |> Repo.all()
  end

  @doc """
  Gets a single blog post idea with its author and ordered comments preloaded.
  Returns `nil` when the idea does not exist.
  """
  def get_blog_post_idea(id) when is_binary(id) do
    BlogPostIdea
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      idea ->
        Repo.preload(idea, [
          :author,
          comments: from(comment in BlogPostIdeaComment, order_by: [asc: comment.inserted_at], preload: [:author])
        ])
    end
  end

  @doc """
  Creates a blog post idea. `author` is optional and records who captured it
  (nil for agent or Slack-originated captures).

  Pass `announce: true` to broadcast the new idea to the company Slack
  #marketing channel (async, via an Oban job). Defaults to not announcing so
  seeds, backfills, and tests stay silent.
  """
  def create_blog_post_idea(attrs, author \\ nil, opts \\ []) when is_map(attrs) and is_list(opts) do
    changeset =
      %BlogPostIdea{author_id: author && author.id}
      |> BlogPostIdea.changeset(attrs)

    result = Repo.insert(changeset)

    with {:ok, idea} <- result, true <- Keyword.get(opts, :announce, false) do
      enqueue_announcement(idea)
    end

    case result do
      {:ok, idea} ->
        Search.index_blog_post_idea(idea)
        audit_blog_post_idea("blog_post_idea.created", idea, changeset, actor: author)

      _result ->
        :ok
    end

    result
  end

  defp enqueue_announcement(%BlogPostIdea{id: id}) do
    %{"blog_post_idea_id" => id}
    |> PostBlogPostIdeaAnnouncement.new()
    |> Oban.insert()
  end

  @doc """
  Records the Slack thread an idea was announced in so later replies in that
  thread can be captured back onto the idea.
  """
  def set_blog_post_idea_slack_thread(%BlogPostIdea{} = idea, thread_ts) when is_binary(thread_ts) do
    changeset = BlogPostIdea.slack_thread_changeset(idea, %{slack_thread_ts: thread_ts})

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        Search.index_blog_post_idea(updated)
        audit_blog_post_idea("blog_post_idea.slack_thread_set", updated, changeset)

      _result ->
        :ok
    end)
  end

  @doc """
  Finds the idea announced in the given Slack thread, if any.
  """
  def get_blog_post_idea_by_slack_thread(thread_ts) when is_binary(thread_ts) do
    BlogPostIdea
    |> where([idea], idea.slack_thread_ts == ^thread_ts)
    |> Repo.one()
  end

  def get_blog_post_idea_by_slack_thread(_thread_ts), do: nil

  def change_blog_post_idea(%BlogPostIdea{} = idea, attrs \\ %{}) when is_map(attrs) do
    BlogPostIdea.changeset(idea, attrs)
  end

  def update_blog_post_idea(%BlogPostIdea{} = idea, attrs) when is_map(attrs) do
    changeset = BlogPostIdea.changeset(idea, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        Search.index_blog_post_idea(updated)
        audit_blog_post_idea("blog_post_idea.updated", updated, changeset)

      _result ->
        :ok
    end)
  end

  def change_blog_post_idea_comment(%BlogPostIdea{} = idea, attrs \\ %{}) do
    %BlogPostIdeaComment{blog_post_idea_id: idea.id}
    |> BlogPostIdeaComment.changeset(attrs)
  end

  @doc """
  Adds a follow-up comment to a blog post idea. `author` is optional.
  """
  def create_blog_post_idea_comment(%BlogPostIdea{} = idea, attrs, author \\ nil) when is_map(attrs) do
    changeset =
      %BlogPostIdeaComment{
        blog_post_idea_id: idea.id,
        author_id: author && author.id
      }
      |> BlogPostIdeaComment.changeset(attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, comment} ->
        audit_blog_post_idea(
          "blog_post_idea.comment_created",
          idea,
          %{"comment_id" => comment.id, "changed" => Audit.changeset_changes(changeset)},
          actor: author
        )

      _result ->
        :ok
    end)
  end

  @doc """
  Lists social-channel ideas, newest first within each workflow status.
  """
  def list_social_channel_ideas do
    SocialChannelIdea
    |> order_by([idea],
      asc:
        fragment(
          "CASE ? WHEN 'idea' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END",
          idea.status
        ),
      desc: idea.inserted_at
    )
    |> preload([:author])
    |> Repo.all()
  end

  @doc """
  Gets a single social-channel idea with its author and post revisions preloaded.
  Returns `nil` when the idea does not exist.
  """
  def get_social_channel_idea(id) when is_binary(id) do
    SocialChannelIdea
    |> Repo.get(id)
    |> preload_social_channel_idea()
  end

  @doc """
  Creates a social-channel idea. `author` is optional and records who captured
  it when the capture came from the dashboard or an authenticated agent.
  """
  def create_social_channel_idea(attrs, author \\ nil) when is_map(attrs) do
    changeset =
      %SocialChannelIdea{author_id: author && author.id}
      |> SocialChannelIdea.changeset(attrs)

    changeset
    |> Repo.insert()
    |> tap(fn
      {:ok, idea} ->
        Search.index_social_channel_idea(idea)
        audit_social_channel_idea("social_channel_idea.created", idea, changeset, actor: author)

      _result ->
        :ok
    end)
  end

  def change_social_channel_idea(%SocialChannelIdea{} = idea, attrs \\ %{}) when is_map(attrs) do
    SocialChannelIdea.changeset(idea, attrs)
  end

  def update_social_channel_idea(%SocialChannelIdea{} = idea, attrs, opts \\ []) when is_map(attrs) do
    changeset = SocialChannelIdea.changeset(idea, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        Search.index_social_channel_idea(updated)
        audit_social_channel_idea("social_channel_idea.updated", updated, changeset, actor: Keyword.get(opts, :actor))

      _result ->
        :ok
    end)
  end

  def delete_social_channel_idea(%SocialChannelIdea{} = idea, opts \\ []) do
    idea
    |> Repo.delete()
    |> tap(fn
      {:ok, deleted} ->
        Search.delete_record("social_channel_idea", deleted.id)

        audit_social_channel_idea(
          "social_channel_idea.deleted",
          deleted,
          %{"status" => deleted.status},
          actor: Keyword.get(opts, :actor)
        )

      _result ->
        :ok
    end)
  end

  @doc """
  Lists post revisions for a social-channel idea, oldest first.
  """
  def list_social_post_revisions(%SocialChannelIdea{} = idea) do
    SocialPostRevision
    |> where([revision], revision.social_channel_idea_id == ^idea.id)
    |> order_by([revision], asc: revision.revision_number)
    |> preload([:author])
    |> Repo.all()
  end

  def get_social_post_revision(id) when is_binary(id) do
    SocialPostRevision
    |> Repo.get(id)
    |> preload_social_post_revision()
  end

  def change_social_post_revision(%SocialChannelIdea{} = idea, attrs \\ %{}) when is_map(attrs) do
    %SocialPostRevision{
      social_channel_idea_id: idea.id,
      revision_number: next_social_post_revision_number(idea)
    }
    |> SocialPostRevision.changeset(attrs)
  end

  def change_existing_social_post_revision(%SocialPostRevision{} = revision, attrs \\ %{}) when is_map(attrs) do
    SocialPostRevision.changeset(revision, attrs)
  end

  def create_social_post_revision(%SocialChannelIdea{} = idea, attrs, author \\ nil, opts \\ [])
      when is_map(attrs) and is_list(opts) do
    result =
      Repo.transaction(fn ->
        normalized_attrs = normalize_post_revision_attrs(attrs, default_status: "draft")

        if Map.get(normalized_attrs, "status") == "approved" do
          draft_other_social_post_revisions(idea.id)
        end

        changeset =
          %SocialPostRevision{
            social_channel_idea_id: idea.id,
            revision_number: next_social_post_revision_number(idea),
            author_id: author && author.id
          }
          |> SocialPostRevision.changeset(normalized_attrs)

        case Repo.insert(changeset) do
          {:ok, revision} ->
            revision = preload_social_post_revision(revision)

            if revision.status == "approved" do
              sync_social_channel_idea_status(revision.social_channel_idea_id,
                actor: Keyword.get(opts, :actor) || author
              )
            end

            audit_social_post_revision("social_post_revision.created", revision, changeset,
              actor: Keyword.get(opts, :actor) || author
            )

            revision

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    # Search indexing performs external embedding/vector I/O, so it runs after the
    # transaction commits to avoid holding the DB connection open across the network
    # round-trip and to keep an indexing failure from rolling back a valid revision.
    with {:ok, revision} <- result do
      index_social_channel_idea_with_revisions(revision.social_channel_idea_id)
      {:ok, revision}
    end
  end

  def update_social_post_revision(%SocialPostRevision{} = revision, attrs, opts \\ []) when is_map(attrs) do
    result =
      Repo.transaction(fn ->
        normalized_attrs = normalize_post_revision_attrs(attrs)
        changeset = SocialPostRevision.changeset(revision, normalized_attrs)
        status_changed? = Map.has_key?(normalized_attrs, "status")

        # Only draft the sibling revisions when this update is actually promoting the
        # revision to approved. Without the status_changed? guard, editing only the
        # body/notes of an already-approved revision would needlessly re-draft (and
        # bump updated_at on) every other revision.
        if status_changed? and Ecto.Changeset.get_field(changeset, :status) == "approved" do
          draft_other_social_post_revisions(revision.social_channel_idea_id, revision.id)
        end

        case Repo.update(changeset) do
          {:ok, updated} ->
            updated = preload_social_post_revision(updated)

            if status_changed? do
              sync_social_channel_idea_status(updated.social_channel_idea_id,
                actor: Keyword.get(opts, :actor)
              )
            end

            audit_social_post_revision("social_post_revision.updated", updated, changeset,
              actor: Keyword.get(opts, :actor)
            )

            updated

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    # Index outside the transaction: see create_social_post_revision/4.
    with {:ok, updated} <- result do
      index_social_channel_idea_with_revisions(updated.social_channel_idea_id)
      {:ok, updated}
    end
  end

  def approve_social_post_revision(%SocialPostRevision{} = revision, opts \\ []) do
    update_social_post_revision(revision, %{"status" => "approved"}, opts)
  end

  def delete_social_post_revision(%SocialPostRevision{} = revision, opts \\ []) do
    revision
    |> Repo.delete()
    |> tap(fn
      {:ok, deleted} ->
        if deleted.status == "approved" do
          sync_social_channel_idea_status(deleted.social_channel_idea_id,
            actor: Keyword.get(opts, :actor)
          )
        end

        index_social_channel_idea_with_revisions(deleted.social_channel_idea_id)

        audit_social_post_revision(
          "social_post_revision.deleted",
          deleted,
          %{"status" => deleted.status, "revision_number" => deleted.revision_number},
          actor: Keyword.get(opts, :actor)
        )

      _result ->
        :ok
    end)
  end

  @doc """
  Lists GTM signal queries. Pass `enabled?: true` to return runnable queries.
  """
  def list_signal_queries(opts \\ []) do
    SignalQuery
    |> maybe_filter_enabled(Keyword.get(opts, :enabled?))
    |> order_by([query], asc: query.source, asc: query.name)
    |> Repo.all()
  end

  def ensure_research_signal_queries(opts \\ []) do
    query_attrs = Topics.signal_queries(opts)

    query_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, queries} ->
      case upsert_signal_query(attrs) do
        {:ok, query} -> {:cont, {:ok, [query | queries]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, queries} ->
        disable_stale_generated_signal_queries(query_attrs, opts)
        {:ok, Enum.reverse(queries)}

      error ->
        error
    end
  end

  def ensure_default_signal_queries, do: ensure_research_signal_queries()

  def upsert_signal_query(attrs) when is_map(attrs) do
    source = attr(attrs, :source)
    query = attr(attrs, :query)

    existing =
      if is_binary(source) and is_binary(query) do
        Repo.get_by(SignalQuery, source: String.trim(source), query: String.trim(query))
      end

    (existing || %SignalQuery{})
    |> SignalQuery.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def change_signal_query(%SignalQuery{} = query, attrs \\ %{}) when is_map(attrs) do
    SignalQuery.changeset(query, attrs)
  end

  def mark_signal_query_run(%SignalQuery{} = query, %DateTime{} = now) do
    query
    |> SignalQuery.mark_run_changeset(now)
    |> Repo.update()
  end

  def scan_gtm_opportunities(opts \\ []) do
    Scanner.run(opts)
  end

  @doc """
  Records one public signal and refreshes its company-level opportunity score.
  """
  def record_gtm_signal(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    Repo.transaction(fn ->
      with {:ok, opportunity} <- upsert_opportunity_for_signal(attrs),
           {:ok, signal} <- upsert_signal(opportunity, attrs),
           {:ok, _contact} <- maybe_upsert_public_mention_contact(opportunity, attrs),
           {:ok, _opportunity} <- refresh_gtm_opportunity_score(opportunity.id) do
        signal
      else
        error -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, signal} ->
        Search.index_gtm_signal(signal)

        signal.opportunity_id
        |> get_gtm_opportunity()
        |> maybe_index_gtm_opportunity()

        maybe_process_found_signal(signal, opts)
        audit_gtm_signal(signal)
        {:ok, signal}

      {:error, error} ->
        error
    end
  end

  def list_gtm_opportunities(opts \\ []) do
    Opportunity
    |> maybe_filter_status(Keyword.get(opts, :status))
    |> maybe_filter_excluded_status(Keyword.get(opts, :exclude_status))
    |> order_gtm_opportunities(Keyword.get(opts, :sort_by), Keyword.get(opts, :sort_order))
    |> limit(^Keyword.get(opts, :limit, 100))
    |> preload([:account, :contacts, :signals])
    |> Repo.all()
  end

  def list_gtm_advocates(opts \\ []) do
    status = Keyword.get(opts, :status)
    exclude_status = Keyword.get(opts, :exclude_status, default_advocate_excluded_status(status))

    OpportunityContact
    |> join(:inner, [contact], opportunity in assoc(contact, :opportunity))
    |> where(
      [contact, _opportunity],
      contact.title == "Public Tuist advocate" or fragment("?->>? = ?", contact.metadata, "source", "public_mention")
    )
    |> maybe_filter_advocate_opportunity_status(status)
    |> maybe_filter_advocate_excluded_opportunity_status(exclude_status)
    |> order_by([contact, opportunity],
      desc: contact.confidence,
      desc_nulls_last: opportunity.latest_signal_at,
      asc: contact.full_name
    )
    |> limit(^Keyword.get(opts, :limit, 25))
    |> preload([_contact, opportunity], opportunity: {opportunity, [:signals]})
    |> Repo.all()
  end

  def opportunity_status_counts do
    Opportunity
    |> group_by([opportunity], opportunity.status)
    |> select([opportunity], {opportunity.status, count(opportunity.id)})
    |> Repo.all()
    |> Map.new()
  end

  def get_gtm_opportunity(id) when is_binary(id) do
    Opportunity
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      opportunity ->
        Repo.preload(opportunity, [
          :account,
          contacts: from(contact in OpportunityContact, order_by: [desc: contact.confidence, asc: contact.title]),
          signals: from(signal in Signal, order_by: [desc: signal.observed_at, desc: signal.inserted_at])
        ])
    end
  end

  def update_gtm_opportunity_status(opportunity_or_id, status, attrs \\ %{})

  def update_gtm_opportunity_status(%Opportunity{} = opportunity, status, attrs)
      when is_binary(status) and is_map(attrs) do
    attrs =
      attrs
      |> Map.drop([:account_id, "account_id"])
      |> Map.put(:status, status)
      |> maybe_put_reviewed_at(status)

    changeset = Opportunity.status_changeset(opportunity, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} ->
        Search.index_gtm_opportunity(updated)
        audit_gtm_opportunity("gtm_opportunity.status_updated", updated, changeset)

      _result ->
        :ok
    end)
  end

  def update_gtm_opportunity_status(id, status, attrs) when is_binary(id) do
    case get_gtm_opportunity(id) do
      nil -> {:error, :not_found}
      opportunity -> update_gtm_opportunity_status(opportunity, status, attrs)
    end
  end

  def refresh_gtm_opportunity_score(id) when is_binary(id) do
    case Repo.get(Opportunity, id) do
      nil ->
        {:error, :not_found}

      opportunity ->
        signals =
          Signal
          |> where([signal], signal.opportunity_id == ^opportunity.id)
          |> Repo.all()

        score_attrs = Scoring.score(signals)

        opportunity
        |> Opportunity.changeset(score_attrs)
        |> Repo.update()
        |> tap(fn
          {:ok, updated} -> Search.index_gtm_opportunity(updated)
          _result -> :ok
        end)
    end
  end

  def enrich_gtm_opportunity_contacts(opportunity_or_id, opts \\ [])

  def enrich_gtm_opportunity_contacts(%Opportunity{} = opportunity, opts) do
    with {:ok, contacts} <- Apollo.search_leaders_for_company(opportunity, opts) do
      contacts
      |> Enum.map(&upsert_opportunity_contact(opportunity, &1))
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, contact}, {:ok, acc} -> {:cont, {:ok, [contact | acc]}}
        {:error, reason}, _acc -> {:halt, {:error, reason}}
      end)
      |> case do
        {:ok, contacts} ->
          contacts = Enum.reverse(contacts)

          audit_gtm_opportunity("gtm_opportunity.contacts_enriched", opportunity, %{
            "contacts_count" => length(contacts)
          })

          {:ok, contacts}

        error ->
          error
      end
    end
  end

  def enrich_gtm_opportunity_contacts(id, opts) when is_binary(id) do
    case get_gtm_opportunity(id) do
      nil -> {:error, :not_found}
      opportunity -> enrich_gtm_opportunity_contacts(opportunity, opts)
    end
  end

  def prepare_gtm_opportunity_for_outreach(opportunity_or_id, opts \\ [])

  def prepare_gtm_opportunity_for_outreach(%Opportunity{} = opportunity, opts) do
    {contacts, contact_error} =
      case enrich_gtm_opportunity_contacts(opportunity, opts) do
        {:ok, contacts} -> {contacts, nil}
        {:error, reason} -> {[], reason}
      end

    with %Opportunity{} = opportunity <- get_gtm_opportunity(opportunity.id),
         {:ok, notified_opportunity} <- notify_gtm_opportunity(opportunity, opts) do
      {:ok, %{opportunity: notified_opportunity, contacts: contacts, contact_error: contact_error}}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def prepare_gtm_opportunity_for_outreach(id, opts) when is_binary(id) do
    case get_gtm_opportunity(id) do
      nil -> {:error, :not_found}
      opportunity -> prepare_gtm_opportunity_for_outreach(opportunity, opts)
    end
  end

  def notify_gtm_opportunity(opportunity_or_id, opts \\ [])

  def notify_gtm_opportunity(%Opportunity{} = opportunity, opts) do
    force? = Keyword.get(opts, :force?, false)
    opportunity = get_gtm_opportunity(opportunity.id) || opportunity

    if not force? and not high_score_gtm_opportunity?(opportunity) do
      {:error, :score_below_threshold}
    else
      with {:ok, attrs} <- SlackNotifier.notify(opportunity, opts) do
        update_gtm_opportunity_slack_notification(opportunity, attrs)
      end
    end
  end

  def notify_gtm_opportunity(id, opts) when is_binary(id) do
    case get_gtm_opportunity(id) do
      nil -> {:error, :not_found}
      opportunity -> notify_gtm_opportunity(opportunity, opts)
    end
  end

  def handle_gtm_opportunity_slack_action(action, opportunity_id, opts \\ [])

  def handle_gtm_opportunity_slack_action(action, opportunity_id, opts)
      when is_binary(action) and is_binary(opportunity_id) do
    case action do
      "find_leaders" ->
        with {:ok, contacts} <- enrich_gtm_opportunity_contacts(opportunity_id, opts),
             {:ok, opportunity} <- refresh_gtm_opportunity_slack_notification(opportunity_id, opts) do
          {:ok,
           %{message: "Added #{length(contacts)} suggested leaders.", opportunity: opportunity, contacts: contacts}}
        end

      "review" ->
        update_gtm_opportunity_from_slack(opportunity_id, "reviewed", "Marked as reviewed.", opts)

      "qualify" ->
        update_gtm_opportunity_from_slack(opportunity_id, "qualified", "Marked as qualified.", opts)

      "reject" ->
        update_gtm_opportunity_from_slack(opportunity_id, "rejected", "Passed for now.", opts)

      "convert" ->
        with {:ok, account, opportunity} <- convert_gtm_opportunity(opportunity_id),
             {:ok, opportunity} <- refresh_gtm_opportunity_slack_notification(opportunity, opts) do
          {:ok,
           %{
             message: "Converted #{account.name} into a prospect account.",
             opportunity: opportunity,
             account: account
           }}
        end

      _action ->
        {:error, :unsupported_gtm_slack_action}
    end
  end

  def handle_gtm_opportunity_slack_action(_action, _opportunity_id, _opts), do: {:error, :invalid_slack_action}

  def convert_gtm_opportunity(opportunity_or_id)

  def convert_gtm_opportunity(%Opportunity{account_id: account_id} = opportunity) when is_binary(account_id) do
    case Repo.get(Account, account_id) do
      nil -> convert_gtm_opportunity(%{opportunity | account_id: nil})
      account -> {:ok, account, opportunity}
    end
  end

  def convert_gtm_opportunity(%Opportunity{} = opportunity) do
    with {:ok, account} <- find_or_create_account_for_opportunity(opportunity),
         {:ok, updated_opportunity} <- mark_gtm_opportunity_converted(opportunity, account) do
      Search.index_gtm_opportunity(updated_opportunity)

      audit_gtm_opportunity("gtm_opportunity.converted", updated_opportunity, %{
        "account_id" => account.id,
        "account_path" => "/sales/accounts/#{account.id}"
      })

      {:ok, account, updated_opportunity}
    end
  end

  def convert_gtm_opportunity(id) when is_binary(id) do
    case get_gtm_opportunity(id) do
      nil -> {:error, :not_found}
      opportunity -> convert_gtm_opportunity(opportunity)
    end
  end

  defp preload_social_channel_idea(nil), do: nil

  defp preload_social_channel_idea(%SocialChannelIdea{} = idea) do
    Repo.preload(idea, [
      :author,
      post_revisions:
        from(revision in SocialPostRevision,
          order_by: [asc: revision.revision_number],
          preload: [:author]
        )
    ])
  end

  defp preload_social_post_revision(nil), do: nil

  defp preload_social_post_revision(%SocialPostRevision{} = revision) do
    Repo.preload(revision, [:author, :social_channel_idea])
  end

  defp next_social_post_revision_number(%SocialChannelIdea{id: idea_id}) when is_binary(idea_id) do
    SocialPostRevision
    |> where([revision], revision.social_channel_idea_id == ^idea_id)
    |> select([revision], max(revision.revision_number))
    |> Repo.one()
    |> case do
      nil -> 1
      number -> number + 1
    end
  end

  defp normalize_post_revision_attrs(attrs, opts \\ []) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    case Keyword.get(opts, :default_status) do
      nil ->
        attrs

      default_status ->
        Map.update(attrs, "status", default_status, fn
          nil -> default_status
          status -> status
        end)
    end
  end

  defp draft_other_social_post_revisions(idea_id, except_revision_id \\ nil) do
    SocialPostRevision
    |> where([revision], revision.social_channel_idea_id == ^idea_id)
    |> maybe_exclude_social_post_revision(except_revision_id)
    |> Repo.update_all(set: [status: "draft", updated_at: NaiveDateTime.utc_now(:second)])
  end

  defp maybe_exclude_social_post_revision(query, nil), do: query

  defp maybe_exclude_social_post_revision(query, revision_id) do
    where(query, [revision], revision.id != ^revision_id)
  end

  defp sync_social_channel_idea_status(idea_id, opts) do
    idea = Repo.get(SocialChannelIdea, idea_id)

    if idea do
      status =
        if approved_social_post_revision_exists?(idea_id) do
          "approved"
        else
          "idea"
        end

      if idea.status == status do
        {:ok, idea}
      else
        changeset = SocialChannelIdea.changeset(idea, %{"status" => status})

        changeset
        |> Repo.update()
        |> tap(fn
          {:ok, updated} ->
            # The caller re-indexes the idea with its revisions preloaded right after
            # this sync, so indexing the partially-loaded idea here would be redundant.
            audit_social_channel_idea("social_channel_idea.updated", updated, changeset,
              actor: Keyword.get(opts, :actor)
            )

          _result ->
            :ok
        end)
      end
    end
  end

  defp approved_social_post_revision_exists?(idea_id) do
    SocialPostRevision
    |> where([revision], revision.social_channel_idea_id == ^idea_id and revision.status == "approved")
    |> Repo.exists?()
  end

  defp index_social_channel_idea_with_revisions(idea_id) do
    idea_id
    |> get_social_channel_idea()
    |> case do
      nil -> :ok
      idea -> Search.index_social_channel_idea(idea)
    end
  end

  defp audit_blog_post_idea(action, %BlogPostIdea{} = idea, metadata_or_changeset, opts \\ []) do
    Audit.record(
      action,
      %{
        target_type: "blog_post_idea",
        target_id: idea.id,
        target_label: idea.title,
        metadata: audit_metadata(metadata_or_changeset)
      },
      opts
    )
  end

  defp audit_social_channel_idea(action, %SocialChannelIdea{} = idea, metadata_or_changeset, opts) do
    Audit.record(
      action,
      %{
        target_type: "social_channel_idea",
        target_id: idea.id,
        target_label: idea.title,
        metadata: audit_metadata(metadata_or_changeset)
      },
      opts
    )
  end

  defp audit_social_post_revision(action, %SocialPostRevision{} = revision, metadata_or_changeset, opts) do
    idea = revision.social_channel_idea

    Audit.record(
      action,
      %{
        target_type: "social_post_revision",
        target_id: revision.id,
        target_label: social_post_revision_label(revision),
        metadata:
          metadata_or_changeset
          |> audit_metadata()
          |> Map.merge(%{
            "path" => "/gtm/social/#{revision.social_channel_idea_id}",
            "social_channel_idea_id" => revision.social_channel_idea_id,
            "social_channel_idea_title" => idea && idea.title,
            "revision_number" => revision.revision_number
          })
      },
      opts
    )
  end

  defp audit_gtm_opportunity(action, %Opportunity{} = opportunity, metadata_or_changeset, opts \\ []) do
    Audit.record(
      action,
      %{
        target_type: "gtm_opportunity",
        target_id: opportunity.id,
        target_label: opportunity.company_name,
        metadata: audit_metadata(metadata_or_changeset)
      },
      opts
    )
  end

  defp audit_gtm_signal(%Signal{} = signal) do
    opportunity = Repo.get(Opportunity, signal.opportunity_id)

    Audit.record("gtm_signal.recorded", %{
      target_type: "gtm_opportunity",
      target_id: signal.opportunity_id,
      target_label: opportunity && opportunity.company_name,
      metadata: %{
        "signal_id" => signal.id,
        "source" => signal.source,
        "source_ref" => signal.source_ref,
        "signal_kind" => signal.signal_kind
      }
    })
  end

  defp audit_metadata(%Ecto.Changeset{} = changeset), do: %{"changed" => Audit.changeset_changes(changeset)}
  defp audit_metadata(nil), do: %{}
  defp audit_metadata(metadata) when is_map(metadata), do: metadata
  defp audit_metadata(value), do: %{"value" => value}

  defp social_post_revision_label(%SocialPostRevision{} = revision) do
    case revision.social_channel_idea do
      %SocialChannelIdea{title: title} when is_binary(title) ->
        "#{title} revision #{revision.revision_number}"

      _idea ->
        "Social post revision #{revision.revision_number}"
    end
  end

  defp maybe_process_found_signal(%Signal{} = signal, opts) do
    if Keyword.get(opts, :prepare_high_score?, false) do
      signal.opportunity_id
      |> get_gtm_opportunity()
      |> maybe_prepare_high_score_opportunity(opts)
    end

    :ok
  end

  defp maybe_index_gtm_opportunity(%Opportunity{} = opportunity), do: Search.index_gtm_opportunity(opportunity)
  defp maybe_index_gtm_opportunity(_opportunity), do: :ok

  defp maybe_prepare_high_score_opportunity(%Opportunity{} = opportunity, opts) do
    if high_score_gtm_opportunity?(opportunity) do
      case prepare_gtm_opportunity_for_outreach(opportunity, opts) do
        {:ok, _result} ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to prepare GTM opportunity #{opportunity.id} for outreach: #{inspect(reason)}")
          :ok
      end
    end
  end

  defp maybe_prepare_high_score_opportunity(_opportunity, _opts), do: :ok

  defp high_score_gtm_opportunity?(%Opportunity{score: score}) when is_integer(score) do
    score >= high_score_threshold()
  end

  defp high_score_gtm_opportunity?(_opportunity), do: false

  defp high_score_threshold do
    :atlas
    |> Application.get_env(:gtm_outreach, [])
    |> Keyword.get(:high_score_threshold, 70)
  end

  defp update_gtm_opportunity_slack_notification(%Opportunity{} = opportunity, attrs) do
    attrs =
      attrs
      |> Map.take([:slack_notification_channel_id, :slack_notification_thread_ts, :slack_notification_posted_at])
      |> Map.put_new(:slack_notification_posted_at, DateTime.utc_now() |> DateTime.truncate(:second))

    changeset = Opportunity.slack_notification_changeset(opportunity, attrs)

    changeset
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_gtm_opportunity("gtm_opportunity.slack_notified", updated, changeset)
      _result -> :ok
    end)
  end

  defp refresh_gtm_opportunity_slack_notification(opportunity_or_id, opts) do
    with %Opportunity{} = opportunity <- reload_gtm_opportunity(opportunity_or_id),
         {:ok, refreshed} <- notify_gtm_opportunity(opportunity, Keyword.put(opts, :force?, true)) do
      {:ok, refreshed}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reload_gtm_opportunity(%Opportunity{id: id}), do: get_gtm_opportunity(id)
  defp reload_gtm_opportunity(id) when is_binary(id), do: get_gtm_opportunity(id)

  defp update_gtm_opportunity_from_slack(opportunity_id, status, message, opts) do
    with {:ok, _opportunity} <- update_gtm_opportunity_status(opportunity_id, status),
         {:ok, opportunity} <- refresh_gtm_opportunity_slack_notification(opportunity_id, opts) do
      {:ok, %{message: message, opportunity: opportunity}}
    end
  end

  defp mark_gtm_opportunity_converted(%Opportunity{} = opportunity, %Account{} = account) do
    attrs =
      %{}
      |> Map.put(:status, "converted")
      |> maybe_put_reviewed_at("converted")

    opportunity
    |> Ecto.Changeset.change(account_id: account.id)
    |> Opportunity.status_changeset(attrs)
    |> Repo.update()
  end

  defp maybe_filter_enabled(query, nil), do: query
  defp maybe_filter_enabled(query, enabled?), do: where(query, [signal_query], signal_query.enabled == ^enabled?)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: where(query, [opportunity], opportunity.status == ^status)

  defp maybe_filter_excluded_status(query, nil), do: query
  defp maybe_filter_excluded_status(query, ""), do: query

  defp maybe_filter_excluded_status(query, status) do
    where(query, [opportunity], opportunity.status != ^status)
  end

  defp default_advocate_excluded_status(status) when is_binary(status) and status != "", do: nil
  defp default_advocate_excluded_status(_status), do: "rejected"

  defp maybe_filter_advocate_opportunity_status(query, nil), do: query
  defp maybe_filter_advocate_opportunity_status(query, ""), do: query

  defp maybe_filter_advocate_opportunity_status(query, status) do
    where(query, [_contact, opportunity], opportunity.status == ^status)
  end

  defp maybe_filter_advocate_excluded_opportunity_status(query, nil), do: query
  defp maybe_filter_advocate_excluded_opportunity_status(query, ""), do: query

  defp maybe_filter_advocate_excluded_opportunity_status(query, status) do
    where(query, [_contact, opportunity], opportunity.status != ^status)
  end

  defp order_gtm_opportunities(query, "company", "asc") do
    order_by(query, [opportunity],
      asc: opportunity.company_name,
      desc: opportunity.score,
      desc_nulls_last: opportunity.latest_signal_at,
      desc: opportunity.inserted_at
    )
  end

  defp order_gtm_opportunities(query, "company", _order) do
    order_by(query, [opportunity],
      desc: opportunity.company_name,
      desc: opportunity.score,
      desc_nulls_last: opportunity.latest_signal_at,
      desc: opportunity.inserted_at
    )
  end

  defp order_gtm_opportunities(query, "status", "asc") do
    order_by(query, [opportunity],
      asc: opportunity.status,
      desc: opportunity.score,
      desc_nulls_last: opportunity.latest_signal_at,
      desc: opportunity.inserted_at
    )
  end

  defp order_gtm_opportunities(query, "status", _order) do
    order_by(query, [opportunity],
      desc: opportunity.status,
      desc: opportunity.score,
      desc_nulls_last: opportunity.latest_signal_at,
      desc: opportunity.inserted_at
    )
  end

  defp order_gtm_opportunities(query, _sort_by, "asc") do
    order_by(query, [opportunity],
      asc: opportunity.score,
      desc_nulls_last: opportunity.latest_signal_at,
      desc: opportunity.inserted_at
    )
  end

  defp order_gtm_opportunities(query, _sort_by, _order) do
    order_by(query, [opportunity],
      desc: opportunity.score,
      desc_nulls_last: opportunity.latest_signal_at,
      desc: opportunity.inserted_at
    )
  end

  defp disable_stale_generated_signal_queries(query_attrs, opts) do
    active_refs = MapSet.new(query_attrs, &{attr(&1, :source), attr(&1, :query)})
    generated_sources = generated_topic_sources(opts)

    SignalQuery
    |> where([query], query.enabled == true)
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(active_refs, {&1.source, &1.query}))
    |> Enum.filter(&(Map.get(&1.metadata, "topic_source") in generated_sources))
    |> Enum.each(fn query ->
      query
      |> SignalQuery.changeset(%{enabled: false})
      |> Repo.update()
    end)
  end

  defp generated_topic_sources(_opts), do: ["curated"]

  defp upsert_opportunity_for_signal(attrs) do
    opportunity_attrs = %{
      company_key: normalize_company_key(attr(attrs, :company_key), attr(attrs, :company_name), attr(attrs, :domain)),
      company_name: normalize_company_name(attr(attrs, :company_name), attr(attrs, :domain), attr(attrs, :company_key)),
      domain: normalize_domain(attr(attrs, :domain))
    }

    case find_opportunity(opportunity_attrs.company_key, opportunity_attrs.domain) do
      nil ->
        %Opportunity{}
        |> Opportunity.changeset(opportunity_attrs)
        |> Repo.insert()

      opportunity ->
        opportunity
        |> Opportunity.changeset(Map.reject(opportunity_attrs, fn {_key, value} -> is_nil(value) end))
        |> Repo.update()
    end
  end

  defp upsert_signal(%Opportunity{} = opportunity, attrs) do
    signal_attrs =
      attrs
      |> Map.take([
        :source,
        :source_ref,
        :source_url,
        :title,
        :excerpt,
        :matched_terms,
        :signal_kind,
        :confidence,
        :observed_at,
        :metadata,
        :query_id
      ])
      |> Map.put(:opportunity_id, opportunity.id)

    %Signal{}
    |> Signal.changeset(signal_attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at, :source, :source_ref, :opportunity_id, :query_id]},
      conflict_target: [:source, :source_ref],
      returning: true
    )
  end

  defp upsert_opportunity_contact(%Opportunity{} = opportunity, attrs) do
    attrs = Map.drop(attrs, [:opportunity_id, "opportunity_id"])

    case find_existing_contact(opportunity, attrs) do
      nil -> %OpportunityContact{opportunity_id: opportunity.id}
      contact -> contact
    end
    |> OpportunityContact.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp maybe_upsert_public_mention_contact(%Opportunity{} = opportunity, attrs) do
    case public_mention_contact_attrs(attrs) do
      nil -> {:ok, nil}
      contact_attrs -> upsert_opportunity_contact(opportunity, contact_attrs)
    end
  end

  defp public_mention_contact_attrs(attrs) do
    metadata = attr(attrs, :metadata) || %{}
    person = metadata_value(metadata, "person")
    source = attr(attrs, :source) || "manual"
    confidence = attr(attrs, :confidence) || 70

    public_mention_contact_attrs(person, source, confidence)
  end

  defp public_mention_contact_attrs(person, source, signal_confidence) when is_map(person) do
    full_name = metadata_value(person, "name") || metadata_value(person, "login")

    if is_binary(full_name) and full_name != "" do
      %{
        source: source,
        full_name: full_name,
        title: metadata_value(person, "title") || "Public Tuist advocate",
        organization_name: metadata_value(person, "company"),
        linkedin_url: metadata_value(person, "linkedin_url"),
        email: metadata_value(person, "email"),
        confidence: metadata_value(person, "confidence") || min(signal_confidence, 90),
        metadata: public_mention_contact_metadata(person)
      }
    end
  end

  defp public_mention_contact_attrs(_person, _source, _signal_confidence), do: nil

  defp public_mention_contact_metadata(person) do
    %{
      "source" => "public_mention",
      "github_login" => metadata_value(person, "login"),
      "github_url" => metadata_value(person, "github_url"),
      "blog" => metadata_value(person, "blog")
    }
  end

  defp find_existing_contact(opportunity, %{linkedin_url: linkedin_url})
       when is_binary(linkedin_url) and linkedin_url != "" do
    Repo.get_by(OpportunityContact, opportunity_id: opportunity.id, linkedin_url: linkedin_url)
  end

  defp find_existing_contact(opportunity, %{metadata: %{"github_url" => github_url}})
       when is_binary(github_url) and github_url != "" do
    OpportunityContact
    |> where([contact], contact.opportunity_id == ^opportunity.id)
    |> where([contact], fragment("?->>? = ?", contact.metadata, "github_url", ^github_url))
    |> limit(1)
    |> Repo.one()
  end

  defp find_existing_contact(opportunity, %{metadata: %{"github_login" => github_login}})
       when is_binary(github_login) and github_login != "" do
    OpportunityContact
    |> where([contact], contact.opportunity_id == ^opportunity.id)
    |> where([contact], fragment("?->>? = ?", contact.metadata, "github_login", ^github_login))
    |> limit(1)
    |> Repo.one()
  end

  defp find_existing_contact(opportunity, attrs) do
    full_name = attrs[:full_name]
    title = attrs[:title]

    if is_binary(full_name) and is_binary(title) do
      Repo.get_by(OpportunityContact, opportunity_id: opportunity.id, full_name: full_name, title: title)
    end
  end

  defp find_opportunity(company_key, domain) when is_binary(domain) and domain != "" do
    Repo.get_by(Opportunity, domain: domain) || Repo.get_by(Opportunity, company_key: company_key)
  end

  defp find_opportunity(company_key, _domain), do: Repo.get_by(Opportunity, company_key: company_key)

  defp find_or_create_account_for_opportunity(%Opportunity{} = opportunity) do
    case find_account_for_opportunity(opportunity) do
      %Account{} = account ->
        {:ok, account}

      nil ->
        Accounts.create_account(%{
          account_key: unique_account_key(opportunity),
          name: opportunity.company_name,
          primary_domain: opportunity.domain,
          url: opportunity.domain && "https://#{opportunity.domain}",
          segment: :prospect,
          metadata: %{
            "created_from" => "gtm_opportunity",
            "gtm_opportunity_id" => opportunity.id,
            "gtm_score" => opportunity.score
          }
        })
    end
  end

  defp find_account_for_opportunity(%Opportunity{domain: domain}) when is_binary(domain) and domain != "" do
    Account
    |> where([account], fragment("lower(?) = ?", account.primary_domain, ^String.downcase(domain)))
    |> limit(1)
    |> Repo.one()
  end

  defp find_account_for_opportunity(%Opportunity{company_name: company_name}) do
    Account
    |> where([account], fragment("lower(?) = ?", account.name, ^String.downcase(company_name)))
    |> limit(1)
    |> Repo.one()
  end

  defp unique_account_key(%Opportunity{} = opportunity) do
    base = "gtm:" <> slug(opportunity.domain || opportunity.company_name)

    if Repo.get_by(Account, account_key: base) do
      base <> "-" <> String.slice(opportunity.id, 0, 8)
    else
      base
    end
  end

  defp maybe_put_reviewed_at(attrs, status) when status in ["reviewed", "qualified", "rejected", "converted"] do
    Map.put_new(attrs, :reviewed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp maybe_put_reviewed_at(attrs, _status), do: attrs

  defp normalize_company_key(value, _company_name, _domain) when is_binary(value) and value != "" do
    value |> String.trim() |> String.downcase()
  end

  defp normalize_company_key(_value, _company_name, domain) when is_binary(domain) and domain != "" do
    "domain:" <> normalize_domain(domain)
  end

  defp normalize_company_key(_value, company_name, _domain) when is_binary(company_name) and company_name != "" do
    "company:" <> slug(company_name)
  end

  defp normalize_company_key(_value, _company_name, _domain), do: "company:unknown"

  defp normalize_company_name(value, _domain, _company_key) when is_binary(value) and value != "" do
    String.trim(value)
  end

  defp normalize_company_name(_value, domain, _company_key) when is_binary(domain) and domain != "" do
    domain
    |> normalize_domain()
    |> String.split(".")
    |> List.first()
    |> humanize()
  end

  defp normalize_company_name(_value, _domain, company_key) when is_binary(company_key) and company_key != "" do
    company_key
    |> String.split(":")
    |> List.last()
    |> humanize()
  end

  defp normalize_company_name(_value, _domain, _company_key), do: "Unknown company"

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
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "unknown"
      slug -> slug
    end
  end

  defp humanize(value) do
    value
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp metadata_value(metadata, key) when is_map(metadata) do
    Map.get(metadata, key) || Map.get(metadata, metadata_atom_key(key))
  end

  defp metadata_atom_key("person"), do: :person
  defp metadata_atom_key("name"), do: :name
  defp metadata_atom_key("login"), do: :login
  defp metadata_atom_key("title"), do: :title
  defp metadata_atom_key("company"), do: :company
  defp metadata_atom_key("linkedin_url"), do: :linkedin_url
  defp metadata_atom_key("email"), do: :email
  defp metadata_atom_key("confidence"), do: :confidence
  defp metadata_atom_key("github_url"), do: :github_url
  defp metadata_atom_key("blog"), do: :blog
  defp metadata_atom_key(_key), do: nil
end
