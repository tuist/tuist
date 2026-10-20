defmodule Atlas.MCP.Tools.POCSerializers do
  @moduledoc false

  alias Atlas.MCP.Tool

  def poc(nil), do: nil

  def poc(poc) do
    %{
      "id" => poc.id,
      "account_id" => poc.account_id,
      "account_name" => account_name(poc),
      "title" => poc.title,
      "status" => poc.status,
      "hosting" => poc.hosting,
      "starts_on" => date(poc.starts_on),
      "ends_on" => date(poc.ends_on),
      "summary" => poc.summary,
      "public_token" => poc.public_token,
      "public_url" => public_url(poc),
      "brand_accent_color" => poc.brand_accent_color,
      "brand_logo_url" => poc.brand_logo_url,
      "dashboard_path" => "/commercial/sales/pocs/#{poc.id}",
      "context" => context(poc),
      "scope_features" => scope_features(poc),
      "timeline_entries" => timeline_entries(poc),
      "inserted_at" => Tool.iso8601(poc.inserted_at),
      "updated_at" => Tool.iso8601(poc.updated_at)
    }
  end

  def poc_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "account_name" => %{"type" => ["string", "null"]},
        "title" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "hosting" => %{"type" => "string"},
        "starts_on" => %{"type" => ["string", "null"]},
        "ends_on" => %{"type" => ["string", "null"]},
        "summary" => %{"type" => ["string", "null"]},
        "public_token" => %{"type" => ["string", "null"]},
        "public_url" => %{"type" => ["string", "null"]},
        "brand_accent_color" => %{"type" => ["string", "null"]},
        "brand_logo_url" => %{"type" => ["string", "null"]},
        "dashboard_path" => %{"type" => "string"},
        "context" => %{
          "type" => ["object", "null"],
          "properties" => %{
            "developer_count" => %{"type" => ["integer", "null"]},
            "ci_solution" => %{"type" => ["string", "null"]},
            "git_forge" => %{"type" => ["string", "null"]},
            "primary_language" => %{"type" => ["string", "null"]},
            "monorepo" => %{"type" => ["boolean", "null"]},
            "notes" => %{"type" => ["string", "null"]}
          }
        },
        "scope_features" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "feature_interest_id" => %{"type" => "string"},
              "title" => %{"type" => "string"}
            }
          }
        },
        "timeline_entries" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "occurred_on" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "body" => %{"type" => ["string", "null"]},
              "kind" => %{"type" => "string"},
              "author_label" => %{"type" => ["string", "null"]}
            }
          }
        },
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "account_id",
        "title",
        "status",
        "hosting",
        "dashboard_path",
        "scope_features",
        "timeline_entries",
        "inserted_at",
        "updated_at"
      ]
    }
  end

  def timeline_entry_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "poc_id" => %{"type" => "string"},
        "occurred_on" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "body" => %{"type" => ["string", "null"]},
        "kind" => %{"type" => "string"},
        "author_label" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "poc_id", "occurred_on", "title", "kind"]
    }
  end

  def timeline_entry(nil), do: nil

  def timeline_entry(entry) do
    %{
      "id" => entry.id,
      "poc_id" => entry.poc_id,
      "occurred_on" => date(entry.occurred_on),
      "title" => entry.title,
      "body" => entry.body,
      "kind" => entry.kind,
      "author_label" => entry.author_label
    }
  end

  defp account_name(%{account: %{name: name}}) when is_binary(name), do: name
  defp account_name(_poc), do: nil

  defp context(%{context: nil}), do: nil

  defp context(%{context: context}) do
    %{
      "developer_count" => context.developer_count,
      "ci_solution" => context.ci_solution,
      "git_forge" => context.git_forge,
      "primary_language" => context.primary_language,
      "monorepo" => context.monorepo,
      "notes" => context.notes
    }
  end

  defp context(_poc), do: nil

  defp scope_features(%{scope_features: features}) when is_list(features) do
    Enum.map(features, fn scope ->
      %{
        "feature_interest_id" => scope.feature_interest_id,
        "title" => scope.feature_interest && scope.feature_interest.title
      }
    end)
  end

  defp scope_features(_poc), do: []

  defp timeline_entries(%{timeline_entries: entries}) when is_list(entries), do: Enum.map(entries, &timeline_entry/1)

  defp timeline_entries(_poc), do: []

  defp public_url(%{public_token: nil}), do: nil

  defp public_url(%{public_token: token}) when is_binary(token) do
    AtlasWeb.Endpoint.url() <> "/p/pocs/#{token}"
  end

  defp public_url(_poc), do: nil

  defp date(nil), do: nil
  defp date(%Date{} = date), do: Date.to_iso8601(date)
end
