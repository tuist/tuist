defmodule Atlas.Search do
  @moduledoc """
  Shared semantic search index for prose-heavy Atlas resources.

  Postgres stores the searchable record metadata and powers the lexical half of
  hybrid search. The in-cluster vector service stores embeddings keyed by
  `"search_record:<id>"` and is treated as best-effort, matching the document
  and memory search paths.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.Documents.Embedding
  alias Atlas.GTM.BlogPostIdea
  alias Atlas.GTM.Opportunity
  alias Atlas.GTM.Signal
  alias Atlas.GTM.SocialChannelIdea
  alias Atlas.Notes.Note
  alias Atlas.Repo
  alias Atlas.Search.Record
  alias Atlas.Vector

  require Logger

  @vector_source_type "atlas_search_record"

  @default_limit 10
  @search_vector_timeout 1_000
  @search_embedding_receive_timeout 1_000
  @search_vector_receive_timeout 1_000
  @rrf_k 60

  def source_types, do: Record.source_types()

  def index_account_event(%Event{} = event, opts \\ []) do
    upsert_record(
      %{
        source_type: "account_event",
        source_id: event.id,
        account_id: event.account_id,
        title: first_present([event.title, event.kind, "Account event"]),
        body: event.body,
        path: account_path(event.account_id),
        metadata:
          compact_map(%{
            "source" => event.source,
            "kind" => event.kind,
            "occurred_at" => iso8601(event.occurred_at),
            "url" => event.url
          })
      },
      opts
    )
  end

  def index_account_outcome(%Outcome{} = outcome, opts \\ []) do
    upsert_record(
      %{
        source_type: "account_outcome",
        source_id: outcome.id,
        account_id: outcome.account_id,
        title: first_present([outcome.title, "Account outcome"]),
        body:
          join_text([
            outcome.description,
            outcome.success_measure,
            outcome.baseline,
            outcome.target
          ]),
        path: account_path(outcome.account_id),
        metadata:
          compact_map(%{
            "status" => outcome.status,
            "health" => outcome.health,
            "motion" => outcome.motion,
            "target_date" => iso8601(outcome.target_date),
            "reviewed_at" => iso8601(outcome.reviewed_at),
            "achieved_at" => iso8601(outcome.achieved_at)
          })
      },
      opts
    )
  end

  def index_account_overview_summary(account, opts \\ [])

  def index_account_overview_summary(%Account{overview_summary: summary} = account, opts) when is_binary(summary) do
    upsert_record(
      %{
        source_type: "account_overview_summary",
        source_id: account.id,
        account_id: account.id,
        title: "#{account.name} overview summary",
        body: summary,
        path: account_path(account.id),
        metadata:
          compact_map(%{
            "account_name" => account.name,
            "segment" => format_value(account.segment),
            "generated_at" => iso8601(account.overview_summary_generated_at)
          })
      },
      opts
    )
  end

  def index_account_overview_summary(%Account{id: id}, _opts) when is_binary(id) do
    delete_record("account_overview_summary", id)
  end

  def index_gtm_opportunity(%Opportunity{} = opportunity, opts \\ []) do
    upsert_record(
      %{
        source_type: "gtm_opportunity",
        source_id: opportunity.id,
        account_id: opportunity.account_id,
        title: first_present([opportunity.company_name, opportunity.domain, "Go-to-market opportunity"]),
        body: join_text([opportunity.signal_summary, opportunity.rationale, opportunity.rejected_reason]),
        path: "/commercial/gtm/outreach",
        metadata:
          compact_map(%{
            "company_name" => opportunity.company_name,
            "domain" => opportunity.domain,
            "status" => opportunity.status,
            "score" => opportunity.score,
            "latest_signal_at" => iso8601(opportunity.latest_signal_at)
          })
      },
      opts
    )
  end

  def index_gtm_signal(%Signal{} = signal, opts \\ []) do
    opportunity = loaded_or_fetch_opportunity(signal)

    upsert_record(
      %{
        source_type: "gtm_signal",
        source_id: signal.id,
        account_id: opportunity && opportunity.account_id,
        title: first_present([signal.title, "Go-to-market signal"]),
        body: join_text([signal.excerpt, Enum.join(signal.matched_terms || [], ", ")]),
        path: opportunity && "/commercial/gtm/outreach",
        metadata:
          compact_map(%{
            "source" => signal.source,
            "source_ref" => signal.source_ref,
            "source_url" => signal.source_url,
            "signal_kind" => signal.signal_kind,
            "confidence" => signal.confidence,
            "observed_at" => iso8601(signal.observed_at),
            "opportunity_id" => signal.opportunity_id,
            "company_name" => opportunity && opportunity.company_name
          })
      },
      opts
    )
  end

  def index_blog_post_idea(%BlogPostIdea{} = idea, opts \\ []) do
    upsert_record(
      %{
        source_type: "blog_post_idea",
        source_id: idea.id,
        title: first_present([idea.title, "Blog post idea"]),
        body: idea.description,
        path: "/commercial/gtm/content/#{idea.id}",
        metadata:
          compact_map(%{
            "status" => idea.status,
            "created_by_agent" => idea.created_by_agent,
            "slack_thread_ts" => idea.slack_thread_ts
          })
      },
      opts
    )
  end

  def index_note(%Note{} = note, opts \\ []) do
    upsert_record(
      %{
        source_type: "note",
        source_id: note.id,
        title: note.title,
        body: note.content,
        path: "/library/notes/#{note.id}",
        metadata: %{
          "visibility" => note.visibility,
          "created_by_id" => note.created_by_id
        }
      },
      opts
    )
  end

  def index_social_channel_idea(%SocialChannelIdea{} = idea, opts \\ []) do
    upsert_record(
      %{
        source_type: "social_channel_idea",
        source_id: idea.id,
        title: first_present([idea.title, "Social channel idea"]),
        body: social_channel_idea_body(idea),
        path: "/commercial/gtm/social/#{idea.id}",
        metadata:
          compact_map(%{
            "status" => idea.status,
            "created_by_agent" => idea.created_by_agent,
            "post_revisions_count" => social_post_revisions_count(idea),
            "published_post_revision_id" => published_social_post_revision_id(idea)
          })
      },
      opts
    )
  end

  def upsert_record(attrs, opts \\ []) when is_map(attrs) do
    changeset =
      attrs
      |> Map.update(:body, nil, &blank_to_nil/1)
      |> ensure_body_has_text()
      |> then(fn attrs ->
        (fetch_record(attrs[:source_type], attrs[:source_id]) || %Record{})
        |> put_record_account_id(attrs)
        |> Record.changeset(attrs)
      end)

    changeset
    |> Repo.insert_or_update()
    |> case do
      {:ok, record} ->
        record = maybe_index_record_vector(record, opts)
        {:ok, record}

      {:error, %Ecto.Changeset{} = changeset} = error ->
        case fallback_conflict_update(changeset, attrs, opts) do
          {:ok, _record} = ok -> ok
          :error -> error
        end
    end
  end

  def delete_record(source_type, source_id) when is_binary(source_type) and is_binary(source_id) do
    case fetch_record(source_type, source_id) do
      nil ->
        :ok

      record ->
        _ = Vector.delete_vectors([vector_id(record)])
        Repo.delete(record)
        :ok
    end
  end

  def search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_limit)

    case String.trim(query) do
      "" -> {:ok, []}
      trimmed -> {:ok, hybrid_search(trimmed, opts, limit)}
    end
  end

  def backfill(opts \\ []) do
    {:ok,
     %{
       account_events: backfill(Event, &index_account_event(&1, opts)),
       account_outcomes: backfill(Outcome, &index_account_outcome(&1, opts)),
       account_overview_summaries:
         Account
         |> where([account], not is_nil(account.overview_summary))
         |> backfill_query(&index_account_overview_summary(&1, opts)),
       gtm_opportunities: backfill(Opportunity, &index_gtm_opportunity(&1, opts)),
       gtm_signals: backfill(Signal, &index_gtm_signal(&1, opts)),
       blog_post_ideas: backfill(BlogPostIdea, &index_blog_post_idea(&1, opts)),
       social_channel_ideas: backfill(SocialChannelIdea, &index_social_channel_idea(&1, opts)),
       notes: backfill(Note, &index_note(&1, opts))
     }}
  end

  defp fetch_record(source_type, source_id) do
    if is_binary(source_type) and is_binary(source_id) do
      Repo.get_by(Record, source_type: source_type, source_id: source_id)
    end
  end

  defp fallback_conflict_update(%Ecto.Changeset{} = changeset, attrs, opts) do
    source_type = Ecto.Changeset.get_field(changeset, :source_type)
    source_id = Ecto.Changeset.get_field(changeset, :source_id)

    case fetch_record(source_type, source_id) do
      %Record{} = record ->
        record
        |> put_record_account_id(attrs)
        |> Record.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, maybe_index_record_vector(updated, opts)}
          {:error, _changeset} -> :error
        end

      nil ->
        :error
    end
  end

  defp put_record_account_id(%Record{} = record, %{account_id: account_id}), do: %{record | account_id: account_id}
  defp put_record_account_id(%Record{} = record, _attrs), do: record

  defp maybe_index_record_vector(%Record{} = record, opts) do
    if Keyword.get(opts, :embed?, true) and Vector.configured?() do
      index_record_vector(record, opts)
    else
      record
    end
  end

  defp index_record_vector(%Record{} = record, opts) do
    with {:ok, %{embedding: embedding, model: model}} <-
           Embedding.embed(searchable_text(record), search_embedding_opts(opts)),
         {:ok, _body} <-
           Vector.upsert_vectors([
             %{
               id: vector_id(record),
               vector: embedding,
               attributes: %{
                 "source_type" => @vector_source_type,
                 "record_source_type" => record.source_type,
                 "record_source_id" => record.source_id,
                 "account_id" => record.account_id
               }
             }
           ]) do
      record
      |> Record.embedding_changeset(model, DateTime.utc_now())
      |> Repo.update!()
    else
      {:error, reason} ->
        Logger.warning(
          "Search record embedding skipped for #{record.source_type}:#{record.source_id}: #{inspect(reason)}"
        )

        record

      :disabled ->
        record
    end
  end

  defp hybrid_search(query, opts, limit) do
    candidate_pool = limit * 4
    vector_task = Task.async(fn -> vector_candidates(query, opts, candidate_pool) end)
    fulltext_results = fulltext_candidates(query, opts, candidate_pool)

    [
      await_vector_candidates(vector_task, Keyword.get(opts, :vector_timeout, @search_vector_timeout)),
      fulltext_results
    ]
    |> reciprocal_rank_fusion(candidate_pool, qmd_mode: Keyword.get(opts, :qmd_mode, false))
    |> hydrate_hits(opts, limit)
  end

  defp vector_candidates(query, opts, limit) do
    if Vector.configured?() do
      with {:ok, %{embedding: embedding}} <- Embedding.embed(query, search_embedding_opts(opts)),
           {:ok, body} <-
             Vector.search(embedding,
               k: limit,
               receive_timeout: Keyword.get(opts, :vector_receive_timeout, @search_vector_receive_timeout),
               filter: %{"eq" => %{"field" => "source_type", "value" => @vector_source_type}}
             ) do
        body |> extract_hits() |> Enum.map(&{&1.record_id, &1.score})
      else
        _ -> []
      end
    else
      []
    end
  end

  defp await_vector_candidates(task, timeout) do
    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, results} when is_list(results) -> results
      _result -> []
    end
  end

  defp fulltext_candidates(query, opts, limit) do
    Record
    |> apply_filters(opts)
    |> where(
      [record],
      fragment(
        "to_tsvector('english', coalesce(?, '') || ' ' || coalesce(?, '')) @@ websearch_to_tsquery('english', ?)",
        record.title,
        record.body,
        ^query
      )
    )
    |> order_by([record],
      desc:
        fragment(
          "ts_rank(to_tsvector('english', coalesce(?, '') || ' ' || coalesce(?, '')), websearch_to_tsquery('english', ?))",
          record.title,
          record.body,
          ^query
        )
    )
    |> limit(^limit)
    |> select([record], {
      record.id,
      fragment(
        "ts_rank(to_tsvector('english', coalesce(?, '') || ' ' || coalesce(?, '')), websearch_to_tsquery('english', ?))",
        record.title,
        record.body,
        ^query
      )
    })
    |> Repo.all()
  end

  defp reciprocal_rank_fusion(ranked_lists, limit, opts) do
    weights =
      if Keyword.get(opts, :qmd_mode, false) do
        # QMD gives the original lexical and semantic retrieval paths equal
        # primary weight before applying its position-aware reranking stages.
        [2.0, 2.0]
      else
        [1.0, 1.0]
      end

    ranked_lists
    |> Enum.with_index()
    |> Enum.flat_map(fn {list, list_index} ->
      weight = Enum.at(weights, list_index, 1.0)

      list
      |> Enum.with_index(1)
      |> Enum.map(fn {{id, _score}, rank} ->
        {id, weight / (@rrf_k + rank), rank}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {id, entries} ->
      base_score = Enum.sum(Enum.map(entries, &elem(&1, 1)))
      top_rank = Enum.min(Enum.map(entries, &elem(&1, 2)))
      bonus = qmd_top_rank_bonus(opts, top_rank)
      {id, base_score + bonus}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.take(limit)
  end

  defp qmd_top_rank_bonus(opts, 1) do
    if Keyword.get(opts, :qmd_mode, false), do: 0.05, else: 0.0
  end

  defp qmd_top_rank_bonus(opts, rank) when rank in 2..3 do
    if Keyword.get(opts, :qmd_mode, false), do: 0.02, else: 0.0
  end

  defp qmd_top_rank_bonus(_opts, _rank), do: 0.0

  defp hydrate_hits([], _opts, _limit), do: []

  defp hydrate_hits(hits, opts, limit) do
    ranking = Map.new(hits)
    ids = Map.keys(ranking)

    Record
    |> where([record], record.id in ^ids)
    |> apply_filters(opts)
    |> preload(:account)
    |> Repo.all()
    |> Enum.sort_by(fn record -> -Map.get(ranking, record.id, 0.0) end)
    |> Enum.take(limit)
    |> Enum.map(fn record -> serialize_hit(record, Map.get(ranking, record.id, 0.0)) end)
  end

  defp apply_filters(query, opts) do
    query
    |> maybe_filter_source_types(Keyword.get(opts, :source_types))
    |> maybe_filter_account_id(Keyword.get(opts, :account_id))
  end

  defp maybe_filter_source_types(query, nil), do: query
  defp maybe_filter_source_types(query, []), do: query

  defp maybe_filter_source_types(query, source_types) when is_list(source_types) do
    where(query, [record], record.source_type in ^source_types)
  end

  defp maybe_filter_source_types(query, source_type) when is_binary(source_type) do
    maybe_filter_source_types(query, [source_type])
  end

  defp maybe_filter_account_id(query, nil), do: query
  defp maybe_filter_account_id(query, ""), do: query
  defp maybe_filter_account_id(query, account_id), do: where(query, [record], record.account_id == ^account_id)

  defp extract_hits(%{"results" => results}) when is_list(results) do
    results
    |> Enum.map(&parse_hit/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_hits(_body), do: []

  defp parse_hit(%{"id" => "search_record:" <> record_id} = result) do
    parse_record_hit(record_id, result)
  end

  defp parse_hit(%{"vector" => %{"id" => "search_record:" <> record_id}} = result) do
    parse_record_hit(record_id, result)
  end

  defp parse_hit(_result), do: nil

  defp parse_record_hit(record_id, result) do
    %{record_id: record_id, score: result["score"] || result["distance"]}
  end

  defp search_embedding_opts(opts), do: Keyword.put_new(opts, :receive_timeout, @search_embedding_receive_timeout)

  defp serialize_hit(%Record{} = record, score) do
    %{
      id: record.id,
      source_type: record.source_type,
      source_id: record.source_id,
      account_id: record.account_id,
      account_name: account_name(record),
      title: record.title,
      excerpt: excerpt(record),
      path: record.path,
      metadata: record.metadata || %{},
      score: score,
      inserted_at: iso8601(record.inserted_at),
      updated_at: iso8601(record.updated_at)
    }
  end

  defp account_name(%Record{account: %Account{name: name}}), do: name
  defp account_name(_record), do: nil

  defp excerpt(%Record{} = record) do
    record
    |> searchable_text()
    |> String.slice(0, 1_000)
  end

  defp searchable_text(%Record{title: title, body: body}), do: join_text([title, body])

  defp ensure_body_has_text(%{body: nil, title: title} = attrs), do: Map.put(attrs, :body, title)
  defp ensure_body_has_text(attrs), do: attrs

  defp vector_id(%Record{id: id}), do: "search_record:#{id}"

  defp loaded_or_fetch_opportunity(%Signal{opportunity: %Opportunity{} = opportunity}), do: opportunity

  defp loaded_or_fetch_opportunity(%Signal{opportunity_id: opportunity_id}) when is_binary(opportunity_id) do
    Repo.get(Opportunity, opportunity_id)
  end

  defp loaded_or_fetch_opportunity(_signal), do: nil

  defp backfill(schema, fun), do: schema |> Repo.all() |> backfill_records(fun)
  defp backfill_query(query, fun), do: query |> Repo.all() |> backfill_records(fun)

  defp backfill_records(records, fun) do
    Enum.reduce(records, %{indexed: 0, failed: 0}, fn record, acc ->
      case fun.(record) do
        {:ok, _record} -> Map.update!(acc, :indexed, &(&1 + 1))
        {:error, _reason} -> Map.update!(acc, :failed, &(&1 + 1))
        :ok -> acc
      end
    end)
  end

  defp first_present(values) do
    Enum.find_value(values, fn value ->
      case blank_to_nil(value) do
        nil -> nil
        present -> present
      end
    end)
  end

  defp join_text(values) do
    values
    |> Enum.map(&blank_to_nil/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp social_channel_idea_body(%SocialChannelIdea{} = idea) do
    join_text([idea.description | social_post_revision_bodies(idea)])
  end

  defp social_post_revision_bodies(%SocialChannelIdea{post_revisions: revisions}) when is_list(revisions) do
    Enum.map(revisions, & &1.body)
  end

  defp social_post_revision_bodies(_idea), do: []

  defp social_post_revisions_count(%SocialChannelIdea{post_revisions: revisions}) when is_list(revisions),
    do: length(revisions)

  defp social_post_revisions_count(_idea), do: nil

  defp published_social_post_revision_id(%SocialChannelIdea{post_revisions: revisions}) when is_list(revisions) do
    revisions
    |> Enum.find(&(&1.status == "published"))
    |> case do
      nil -> nil
      revision -> revision.id
    end
  end

  defp published_social_post_revision_id(_idea), do: nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: to_string(value)

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp account_path(account_id) when is_binary(account_id), do: "/commercial/sales/accounts/#{account_id}"
  defp account_path(_account_id), do: nil

  defp format_value(nil), do: nil
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value), do: to_string(value)

  defp iso8601(nil), do: nil
  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso8601(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
  defp iso8601(%Date{} = date), do: Date.to_iso8601(date)
  defp iso8601(value), do: to_string(value)
end
