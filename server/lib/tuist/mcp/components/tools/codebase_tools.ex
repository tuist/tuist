defmodule Tuist.MCP.Components.Tools.CodebaseSchemas do
  @moduledoc false

  def search_output_schema do
    %{
      "type" => "object",
      "properties" => %{
        "revision" => %{"type" => "string"},
        "query" => %{"type" => "string"},
        "matches" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string"},
              "line_number" => %{"type" => "integer"},
              "line" => %{"type" => "string"},
              "context_before" => %{"type" => "array", "items" => %{"type" => "string"}},
              "context_after" => %{"type" => "array", "items" => %{"type" => "string"}},
              "url" => %{"type" => "string"}
            },
            "required" => ["path", "line_number", "line", "context_before", "context_after", "url"],
            "additionalProperties" => false
          }
        },
        "truncated" => %{"type" => "boolean"},
        "truncation_reason" => %{"type" => ["string", "null"]},
        "stats" => %{
          "type" => "object",
          "properties" => %{
            "files_scanned" => %{"type" => "integer"},
            "bytes_scanned" => %{"type" => "integer"},
            "context_bytes_read" => %{"type" => "integer"},
            "files_skipped_too_large" => %{"type" => "integer"},
            "contexts_skipped" => %{"type" => "integer"},
            "file_errors" => %{"type" => "integer"},
            "walk_errors" => %{"type" => "integer"},
            "elapsed_milliseconds" => %{"type" => "integer"}
          },
          "required" => [
            "files_scanned",
            "bytes_scanned",
            "context_bytes_read",
            "files_skipped_too_large",
            "contexts_skipped",
            "file_errors",
            "walk_errors",
            "elapsed_milliseconds"
          ],
          "additionalProperties" => false
        }
      },
      "required" => ["revision", "query", "matches", "truncated", "truncation_reason", "stats"],
      "additionalProperties" => false
    }
  end

  def list_output_schema do
    %{
      "type" => "object",
      "properties" => %{
        "revision" => %{"type" => "string"},
        "entries" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string"},
              "type" => %{"type" => "string", "enum" => ["file", "directory", "symlink"]},
              "url" => %{"type" => "string"}
            },
            "required" => ["path", "type", "url"],
            "additionalProperties" => false
          }
        },
        "truncated" => %{"type" => "boolean"},
        "truncation_reason" => %{"type" => ["string", "null"]},
        "stats" => %{
          "type" => "object",
          "properties" => %{
            "entries_visited" => %{"type" => "integer"},
            "walk_errors" => %{"type" => "integer"},
            "elapsed_milliseconds" => %{"type" => "integer"}
          },
          "required" => ["entries_visited", "walk_errors", "elapsed_milliseconds"],
          "additionalProperties" => false
        }
      },
      "required" => ["revision", "entries", "truncated", "truncation_reason", "stats"],
      "additionalProperties" => false
    }
  end

  def read_output_schema do
    %{
      "type" => "object",
      "properties" => %{
        "revision" => %{"type" => "string"},
        "path" => %{"type" => "string"},
        "start_line" => %{"type" => "integer"},
        "end_line" => %{"type" => "integer"},
        "lines" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "number" => %{"type" => "integer"},
              "text" => %{"type" => "string"}
            },
            "required" => ["number", "text"],
            "additionalProperties" => false
          }
        },
        "file_size_bytes" => %{"type" => "integer"},
        "truncated" => %{"type" => "boolean"},
        "truncation_reason" => %{"type" => ["string", "null"]},
        "next_start_line" => %{"type" => ["integer", "null"]},
        "url" => %{"type" => "string"},
        "elapsed_milliseconds" => %{"type" => "integer"}
      },
      "required" => [
        "revision",
        "path",
        "start_line",
        "end_line",
        "lines",
        "file_size_bytes",
        "truncated",
        "truncation_reason",
        "next_start_line",
        "url",
        "elapsed_milliseconds"
      ],
      "additionalProperties" => false
    }
  end
end

defmodule Tuist.MCP.Components.Tools.SearchTuistCode do
  @moduledoc """
  Searches a fixed revision of the public Tuist source tree with hard resource limits.
  """

  use Tuist.MCP.Tool,
    name: "search_tuist_code",
    title: "Search Tuist Code",
    schema: %{
      "type" => "object",
      "properties" => %{
        "pattern" => %{
          "type" => "string",
          "minLength" => 2,
          "maxLength" => 512,
          "description" => "Text or a regular expression to find in the Tuist source tree."
        },
        "path" => %{
          "type" => "string",
          "maxLength" => 512,
          "description" => "Optional repository-relative file or directory to search."
        },
        "file_glob" => %{
          "type" => "string",
          "maxLength" => 256,
          "description" => "Optional file pattern such as **/*.ex or cli/**/*.swift."
        },
        "use_regular_expression" => %{
          "type" => "boolean",
          "description" => "Interpret pattern as a regular expression. Defaults to false."
        },
        "case_sensitive" => %{
          "type" => "boolean",
          "description" => "Use case-sensitive matching. Defaults to false."
        },
        "context_lines" => %{
          "type" => "integer",
          "minimum" => 0,
          "maximum" => 3,
          "description" => "Context lines returned before and after each match. Defaults to 2."
        },
        "max_results" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 50,
          "description" => "Maximum matches to return. Defaults to 20."
        }
      },
      "required" => ["pattern"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.CodebaseSchemas.search_output_schema()

  alias Tuist.MCP.CodebaseSearch

  @impl EMCP.Tool
  def description do
    "Search a fixed Tuist source revision with bounded traversal, input, time, and output. " <>
      "A truncated response is partial; narrow the path or file_glob and search again."
  end

  def execute(_conn, arguments), do: CodebaseSearch.search(arguments)
end

defmodule Tuist.MCP.Components.Tools.ListTuistFiles do
  @moduledoc """
  Lists bounded portions of a fixed revision of the public Tuist source tree.
  """

  use Tuist.MCP.Tool,
    name: "list_tuist_files",
    title: "List Tuist Files",
    schema: %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "maxLength" => 512,
          "description" => "Optional repository-relative directory. Defaults to the repository root."
        },
        "file_glob" => %{
          "type" => "string",
          "maxLength" => 256,
          "description" => "Optional file pattern such as **/*.rs."
        },
        "depth" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 32,
          "description" => "Maximum traversal depth from path. Defaults to 2."
        },
        "max_results" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 500,
          "description" => "Maximum entries to return. Defaults to 100."
        }
      },
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.CodebaseSchemas.list_output_schema()

  alias Tuist.MCP.CodebaseSearch

  @impl EMCP.Tool
  def description do
    "List files and directories in a fixed Tuist source revision with bounded depth, traversal, time, and output. " <>
      "A truncated response is partial; narrow the path or file_glob and list again."
  end

  def execute(_conn, arguments), do: CodebaseSearch.list_files(arguments)
end

defmodule Tuist.MCP.Components.Tools.ReadTuistFile do
  @moduledoc """
  Reads a bounded line range from a fixed revision of the public Tuist source tree.
  """

  use Tuist.MCP.Tool,
    name: "read_tuist_file",
    title: "Read Tuist File",
    schema: %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 512,
          "description" => "Repository-relative path of the text file to read."
        },
        "start_line" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "First one-based line to return. Defaults to 1."
        },
        "max_lines" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 400,
          "description" => "Maximum lines to return. Defaults to 200."
        }
      },
      "required" => ["path"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.CodebaseSchemas.read_output_schema()

  alias Tuist.MCP.CodebaseSearch

  @impl EMCP.Tool
  def description do
    "Read a bounded line range from a text file in a fixed Tuist source revision. " <>
      "When truncated, continue from next_start_line rather than increasing the limit."
  end

  def execute(_conn, arguments), do: CodebaseSearch.read_file(arguments)
end
