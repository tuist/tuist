defmodule Atlas.MCP.Tools.ListFinanceCategories do
  @moduledoc """
  Lists finance transaction categories in Atlas.
  """

  use Atlas.MCP.Tool,
    name: "list_finance_categories",
    schema: %{
      "type" => "object",
      "properties" => %{
        "direction" => %{
          "type" => "string",
          "enum" => ["credit", "debit"],
          "description" => "Optionally filter categories to those usable for credit or debit transactions."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "categories" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => ["string", "null"]},
              "slug" => %{"type" => ["string", "null"]},
              "description" => %{"type" => ["string", "null"]},
              "direction" => %{"type" => ["string", "null"]},
              "created_by_agent" => %{"type" => ["string", "null"]},
              "metadata" => %{"type" => ["object", "null"]}
            },
            "required" => ["id", "name", "slug", "description", "direction", "created_by_agent", "metadata"],
            "additionalProperties" => false
          }
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["categories", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Finance
  alias Atlas.Finance.Category
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "List broad reusable finance transaction categories."
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "finance:read", "Finance tools") do
      categories =
        args
        |> list_opts()
        |> Finance.list_categories()
        |> Enum.map(&serialize_category/1)

      {:ok, %{categories: categories, count: length(categories)}}
    end
  end

  defp list_opts(args) do
    [
      direction: present(args, "direction")
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp serialize_category(%Category{} = category) do
    %{
      id: category.id,
      name: category.name,
      slug: category.slug,
      description: category.description,
      direction: category.direction,
      created_by_agent: category.created_by_agent,
      metadata: category.metadata
    }
  end

  defp present(args, key) do
    case Map.get(args, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
