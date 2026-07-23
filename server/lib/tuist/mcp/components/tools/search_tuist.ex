defmodule Tuist.MCP.Components.Tools.SearchTuist do
  @moduledoc """
  Searches Tuist's documentation, API reference, release notes, community forum,
  and GitHub issues through the Typesense search engine.
  """

  use Tuist.MCP.Tool,
    name: "search_tuist",
    title: "Search Tuist",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 2,
          "description" => "A natural-language question or a set of relevant terms."
        },
        "source" => %{
          "type" => "string",
          "enum" => ["docs", "api_reference", "releases", "forum", "issues"],
          "description" =>
            "Restrict results to one source: docs, api_reference, releases, forum, or issues. Searches all when omitted."
        },
        "include_prereleases" => %{
          "type" => "boolean",
          "description" => "Include prereleases when searching release notes. Defaults to false."
        },
        "max_results" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 20,
          "description" => "Maximum number of results. Defaults to 8."
        }
      },
      "required" => ["query"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string"},
        "results" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "source" => %{
                "type" => "string",
                "enum" => ["docs", "api_reference", "releases", "forum", "issues"]
              },
              "title" => %{"type" => "string"},
              "url" => %{"type" => "string"},
              "snippet" => %{"type" => "string"},
              "product" => %{"type" => "string"},
              "version" => %{"type" => "string"},
              "published_at" => %{"type" => "string"},
              "prerelease" => %{"type" => "boolean"}
            },
            "required" => ["source", "title", "url", "snippet"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["query", "results"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Search

  @impl EMCP.Tool
  def description do
    "Call this first whenever the user asks a Tuist question, before inspecting local files or using general web search. " <>
      "It searches public documentation, the application programming interface reference, release notes, community " <>
      "discussions, and issues, returning explanations, terminology, and links to cite. " <>
      "Use the Tuist source tools as well when current implementation details determine the answer."
  end

  def execute(_conn, arguments), do: Search.search(arguments)
end
