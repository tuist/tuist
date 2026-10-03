defmodule Atlas.MCP.Serializers.GTM do
  @moduledoc false

  alias Atlas.MCP.Tool

  def list_response(key, items), do: %{key => items, count: length(items)}

  def list_response_schema(key, item_schema) do
    %{
      "type" => "object",
      "properties" => %{
        to_string(key) => %{"type" => "array", "items" => item_schema},
        "count" => %{"type" => "integer"}
      },
      "required" => [to_string(key), "count"],
      "additionalProperties" => false
    }
  end

  def author_schema do
    %{
      "type" => ["object", "null"],
      "properties" => %{
        "name" => %{"type" => ["string", "null"]},
        "email" => %{"type" => ["string", "null"]}
      },
      "required" => ["name", "email"],
      "additionalProperties" => false
    }
  end

  def blog_post_idea(idea) do
    %{
      id: idea.id,
      title: idea.title,
      description: idea.description,
      status: idea.status,
      created_by_agent: idea.created_by_agent,
      author: author(idea),
      inserted_at: Tool.iso8601(idea.inserted_at),
      updated_at: Tool.iso8601(idea.updated_at)
    }
  end

  def blog_post_idea_schema do
    idea_schema()
  end

  def blog_post_idea_with_comments(idea) do
    idea
    |> blog_post_idea()
    |> Map.put(:comments, Enum.map(idea.comments, &comment/1))
  end

  def blog_post_idea_with_comments_schema do
    base = idea_schema()

    %{
      base
      | "properties" => Map.put(base["properties"], "comments", %{"type" => "array", "items" => comment_schema()}),
        "required" => base["required"] ++ ["comments"]
    }
  end

  def social_channel_idea(idea) do
    %{
      id: idea.id,
      title: idea.title,
      description: idea.description,
      status: idea.status,
      created_by_agent: idea.created_by_agent,
      author: author(idea),
      inserted_at: Tool.iso8601(idea.inserted_at),
      updated_at: Tool.iso8601(idea.updated_at)
    }
  end

  def social_channel_idea_schema do
    idea_schema()
  end

  def social_channel_idea_with_post_revisions(idea) do
    idea
    |> social_channel_idea()
    |> Map.put(:post_revisions, association_items(idea, :post_revisions, &social_post_revision/1))
  end

  def social_channel_idea_with_post_revisions_schema do
    base = idea_schema()

    %{
      base
      | "properties" =>
          Map.put(base["properties"], "post_revisions", %{
            "type" => "array",
            "items" => social_post_revision_schema()
          }),
        "required" => base["required"] ++ ["post_revisions"]
    }
  end

  def social_post_revision(revision) do
    %{
      id: revision.id,
      social_channel_idea_id: revision.social_channel_idea_id,
      revision_number: revision.revision_number,
      body: revision.body,
      notes: revision.notes,
      status: revision.status,
      created_by_agent: revision.created_by_agent,
      author: author(revision),
      inserted_at: Tool.iso8601(revision.inserted_at),
      updated_at: Tool.iso8601(revision.updated_at)
    }
  end

  def social_post_revision_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "social_channel_idea_id" => %{"type" => ["string", "null"]},
        "revision_number" => %{"type" => ["integer", "null"]},
        "body" => %{"type" => ["string", "null"]},
        "notes" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "created_by_agent" => %{"type" => ["string", "null"]},
        "author" => author_schema(),
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "social_channel_idea_id",
        "revision_number",
        "body",
        "notes",
        "status",
        "created_by_agent",
        "author",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def comment(comment) do
    %{
      id: comment.id,
      body: comment.body,
      author: author(comment),
      author_name: Map.get(comment, :author_name),
      inserted_at: Tool.iso8601(comment.inserted_at)
    }
  end

  def comment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "author" => author_schema(),
        "author_name" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "body", "author", "author_name", "inserted_at"],
      "additionalProperties" => false
    }
  end

  def opportunity(opportunity) do
    %{
      id: opportunity.id,
      company_key: opportunity.company_key,
      company_name: opportunity.company_name,
      domain: opportunity.domain,
      status: opportunity.status,
      score: opportunity.score,
      score_breakdown: opportunity.score_breakdown,
      rationale: opportunity.rationale,
      signal_summary: opportunity.signal_summary,
      latest_signal_at: Tool.iso8601(opportunity.latest_signal_at),
      reviewed_at: Tool.iso8601(opportunity.reviewed_at),
      slack_notification_channel_id: opportunity.slack_notification_channel_id,
      slack_notification_thread_ts: opportunity.slack_notification_thread_ts,
      slack_notification_posted_at: Tool.iso8601(opportunity.slack_notification_posted_at),
      account_id: opportunity.account_id,
      account_url: opportunity.account_id && Tool.account_url(opportunity.account_id),
      signals_count: association_count(opportunity, :signals),
      contacts_count: association_count(opportunity, :contacts),
      inserted_at: Tool.iso8601(opportunity.inserted_at),
      updated_at: Tool.iso8601(opportunity.updated_at)
    }
  end

  def opportunity_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "company_key" => %{"type" => ["string", "null"]},
        "company_name" => %{"type" => ["string", "null"]},
        "domain" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "score" => %{"type" => ["integer", "null"]},
        "score_breakdown" => %{"type" => ["object", "null"]},
        "rationale" => %{"type" => ["string", "null"]},
        "signal_summary" => %{"type" => ["string", "null"]},
        "latest_signal_at" => %{"type" => ["string", "null"]},
        "reviewed_at" => %{"type" => ["string", "null"]},
        "slack_notification_channel_id" => %{"type" => ["string", "null"]},
        "slack_notification_thread_ts" => %{"type" => ["string", "null"]},
        "slack_notification_posted_at" => %{"type" => ["string", "null"]},
        "account_id" => %{"type" => ["string", "null"]},
        "account_url" => %{"type" => ["string", "null"]},
        # nil rather than 0 when the association was not preloaded.
        "signals_count" => %{"type" => ["integer", "null"]},
        "contacts_count" => %{"type" => ["integer", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "company_key",
        "company_name",
        "domain",
        "status",
        "score",
        "score_breakdown",
        "rationale",
        "signal_summary",
        "latest_signal_at",
        "reviewed_at",
        "slack_notification_channel_id",
        "slack_notification_thread_ts",
        "slack_notification_posted_at",
        "account_id",
        "account_url",
        "signals_count",
        "contacts_count",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def opportunity_with_details(opportunity) do
    opportunity
    |> opportunity()
    |> Map.put(:signals, association_items(opportunity, :signals, &signal/1))
    |> Map.put(:contacts, association_items(opportunity, :contacts, &opportunity_contact/1))
  end

  def opportunity_with_details_schema do
    base = opportunity_schema()

    %{
      base
      | "properties" =>
          Map.merge(base["properties"], %{
            "signals" => %{"type" => "array", "items" => signal_schema()},
            "contacts" => %{"type" => "array", "items" => opportunity_contact_schema()}
          }),
        "required" => base["required"] ++ ["signals", "contacts"]
    }
  end

  def signal(signal) do
    %{
      id: signal.id,
      source: signal.source,
      source_url: signal.source_url,
      title: signal.title,
      excerpt: signal.excerpt,
      matched_terms: signal.matched_terms,
      signal_kind: signal.signal_kind,
      confidence: signal.confidence,
      observed_at: Tool.iso8601(signal.observed_at),
      metadata: signal.metadata
    }
  end

  def signal_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "source" => %{"type" => ["string", "null"]},
        "source_url" => %{"type" => ["string", "null"]},
        "title" => %{"type" => ["string", "null"]},
        "excerpt" => %{"type" => ["string", "null"]},
        "matched_terms" => %{"type" => ["array", "null"], "items" => %{"type" => "string"}},
        "signal_kind" => %{"type" => ["string", "null"]},
        "confidence" => %{"type" => ["integer", "null"]},
        "observed_at" => %{"type" => ["string", "null"]},
        "metadata" => %{"type" => ["object", "null"]}
      },
      "required" => [
        "id",
        "source",
        "source_url",
        "title",
        "excerpt",
        "matched_terms",
        "signal_kind",
        "confidence",
        "observed_at",
        "metadata"
      ],
      "additionalProperties" => false
    }
  end

  def opportunity_contact(contact) do
    %{
      id: contact.id,
      source: contact.source,
      full_name: contact.full_name,
      title: contact.title,
      organization_name: contact.organization_name,
      linkedin_url: contact.linkedin_url,
      email: contact.email,
      confidence: contact.confidence,
      metadata: contact.metadata
    }
  end

  def opportunity_contact_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "source" => %{"type" => ["string", "null"]},
        "full_name" => %{"type" => ["string", "null"]},
        "title" => %{"type" => ["string", "null"]},
        "organization_name" => %{"type" => ["string", "null"]},
        "linkedin_url" => %{"type" => ["string", "null"]},
        "email" => %{"type" => ["string", "null"]},
        "confidence" => %{"type" => ["integer", "null"]},
        "metadata" => %{"type" => ["object", "null"]}
      },
      "required" => [
        "id",
        "source",
        "full_name",
        "title",
        "organization_name",
        "linkedin_url",
        "email",
        "confidence",
        "metadata"
      ],
      "additionalProperties" => false
    }
  end

  def advocate(contact) do
    contact
    |> opportunity_contact()
    |> Map.put(:profile_url, advocate_profile_url(contact))
    |> Map.put(:opportunity, advocate_opportunity(contact))
    |> Map.put(:evidence_signal, advocate_signal(contact))
  end

  def advocate_schema do
    base = opportunity_contact_schema()

    advocate_opportunity_schema = %{
      "type" => ["object", "null"],
      "properties" => %{
        "id" => %{"type" => "string"},
        "company_name" => %{"type" => ["string", "null"]},
        "domain" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "score" => %{"type" => ["integer", "null"]}
      },
      "required" => ["id", "company_name", "domain", "status", "score"],
      "additionalProperties" => false
    }

    %{
      base
      | "properties" =>
          Map.merge(base["properties"], %{
            "profile_url" => %{"type" => ["string", "null"]},
            "opportunity" => advocate_opportunity_schema,
            "evidence_signal" => Tool.nullable(signal_schema())
          }),
        "required" => base["required"] ++ ["profile_url", "opportunity", "evidence_signal"]
    }
  end

  def signal_query(query) do
    %{
      id: query.id,
      name: query.name,
      topic: query.metadata["topic"],
      topic_source: query.metadata["topic_source"],
      source: query.source,
      query: query.query,
      enabled: query.enabled,
      result_limit: query.result_limit,
      last_run_at: Tool.iso8601(query.last_run_at),
      metadata: query.metadata
    }
  end

  def signal_query_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]},
        "topic" => %{"type" => ["string", "null"]},
        "topic_source" => %{"type" => ["string", "null"]},
        "source" => %{"type" => ["string", "null"]},
        "query" => %{"type" => ["string", "null"]},
        "enabled" => %{"type" => ["boolean", "null"]},
        "result_limit" => %{"type" => ["integer", "null"]},
        "last_run_at" => %{"type" => ["string", "null"]},
        "metadata" => %{"type" => ["object", "null"]}
      },
      "required" => [
        "id",
        "name",
        "topic",
        "topic_source",
        "source",
        "query",
        "enabled",
        "result_limit",
        "last_run_at",
        "metadata"
      ],
      "additionalProperties" => false
    }
  end

  # `blog_post_idea/1` and `social_channel_idea/1` serialize to the same shape.
  defp idea_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "description" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "created_by_agent" => %{"type" => ["string", "null"]},
        "author" => author_schema(),
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "title", "description", "status", "created_by_agent", "author", "inserted_at", "updated_at"],
      "additionalProperties" => false
    }
  end

  defp author(%{author: %{name: name, email: email}}) when is_binary(name) or is_binary(email) do
    %{name: name, email: email}
  end

  defp author(_record), do: nil

  defp association_count(record, key) do
    case Map.get(record, key) do
      values when is_list(values) -> length(values)
      _not_loaded -> nil
    end
  end

  defp association_items(record, key, mapper) do
    case Map.get(record, key) do
      values when is_list(values) -> Enum.map(values, mapper)
      _not_loaded -> []
    end
  end

  defp advocate_profile_url(%{linkedin_url: linkedin_url}) when is_binary(linkedin_url) and linkedin_url != "" do
    linkedin_url
  end

  defp advocate_profile_url(%{metadata: %{"github_url" => github_url}})
       when is_binary(github_url) and github_url != "" do
    github_url
  end

  defp advocate_profile_url(_contact), do: nil

  defp advocate_opportunity(%{opportunity: %Ecto.Association.NotLoaded{}}), do: nil

  defp advocate_opportunity(%{opportunity: opportunity}) when is_map(opportunity) do
    %{
      id: opportunity.id,
      company_name: opportunity.company_name,
      domain: opportunity.domain,
      status: opportunity.status,
      score: opportunity.score
    }
  end

  defp advocate_opportunity(_contact), do: nil

  defp advocate_signal(%{opportunity: %{signals: signals}}) when is_list(signals) do
    signals
    |> Enum.sort_by(&signal_sort_timestamp/1, {:desc, DateTime})
    |> then(fn signals ->
      selected_signal = Enum.find(signals, &(&1.signal_kind == "tuist_mention")) || List.first(signals)
      selected_signal && signal(selected_signal)
    end)
  end

  defp advocate_signal(_contact), do: nil

  defp signal_sort_timestamp(%{observed_at: %DateTime{} = observed_at}), do: observed_at
  defp signal_sort_timestamp(_signal), do: ~U[1970-01-01 00:00:00Z]
end
