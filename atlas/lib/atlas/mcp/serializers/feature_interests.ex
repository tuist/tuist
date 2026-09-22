defmodule Atlas.MCP.Serializers.FeatureInterests do
  @moduledoc false

  alias Atlas.MCP.Tool

  def feature_interest(interest) do
    %{
      id: interest.id,
      title: interest.title,
      status: interest.status,
      interest_count: interest.interest_count,
      last_interested_at: Tool.iso8601(interest.last_interested_at)
    }
  end

  def feature_interest_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "interest_count" => %{"type" => "integer"},
        "last_interested_at" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "title", "status", "interest_count", "last_interested_at"],
      "additionalProperties" => false
    }
  end

  def feature_interest_detail(interest) do
    feature_interest(interest)
    |> Map.put(
      :accounts,
      Enum.map(interest.accounts, &account_interest/1)
    )
  end

  def account_interest(interest_account) do
    %{
      id: interest_account.id,
      feature_interest_id: interest_account.feature_interest_id,
      title: interest_account.feature_interest && interest_account.feature_interest.title,
      account_id: interest_account.account.id,
      account_name: interest_account.account.name,
      summary: interest_account.summary,
      notes: interest_account.notes,
      context: interest_account.notes,
      account_event_id: interest_account.account_event_id,
      account_event_path: account_event_path(interest_account),
      support_thread_id: interest_account.support_thread_id,
      last_interested_at: Tool.iso8601(interest_account.last_interested_at)
    }
  end

  def account_interest_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "feature_interest_id" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "account_id" => %{"type" => "string"},
        "account_name" => %{"type" => ["string", "null"]},
        "summary" => %{"type" => "string"},
        "notes" => %{"type" => ["string", "null"]},
        "context" => %{"type" => ["string", "null"]},
        "account_event_id" => %{"type" => ["string", "null"]},
        "account_event_path" => %{"type" => ["string", "null"]},
        "support_thread_id" => %{"type" => ["string", "null"]},
        "last_interested_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "feature_interest_id",
        "title",
        "account_id",
        "account_name",
        "summary",
        "notes",
        "context",
        "account_event_id",
        "account_event_path",
        "support_thread_id",
        "last_interested_at"
      ],
      "additionalProperties" => false
    }
  end

  def feature_interest_detail_schema do
    %{
      "type" => "object",
      "properties" =>
        Map.put(feature_interest_schema()["properties"], "accounts", %{
          "type" => "array",
          "items" => account_interest_schema()
        }),
      "required" => ["id", "title", "status", "interest_count", "last_interested_at", "accounts"],
      "additionalProperties" => false
    }
  end

  defp account_event_path(%{account_event_id: event_id, account_id: account_id})
       when is_binary(event_id) and is_binary(account_id) do
    "/commercial/sales/accounts/#{account_id}#timeline-event-#{event_id}"
  end

  defp account_event_path(_interest_account), do: nil
end
