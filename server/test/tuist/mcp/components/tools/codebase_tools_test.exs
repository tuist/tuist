defmodule Tuist.MCP.Components.Tools.CodebaseToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.CodebaseSearch
  alias Tuist.MCP.Components.Tools.ListTuistFiles
  alias Tuist.MCP.Components.Tools.ReadTuistFile
  alias Tuist.MCP.Components.Tools.SearchTuistCode

  test "descriptions guide agents through source-backed questions" do
    assert SearchTuistCode.description() =~ "current command behavior"
    assert SearchTuistCode.description() =~ "instead of an unrelated local checkout or general web search"
    assert SearchTuistCode.description() =~ "relevant call sites and tests"
    assert SearchTuistCode.description() =~ "truncated response is partial"
    assert ListTuistFiles.description() =~ "relevant Tuist source path is unknown"
    assert ListTuistFiles.description() =~ "instead of enumerating the entire repository"
    assert ReadTuistFile.description() =~ "smallest relevant line range"
    assert ReadTuistFile.description() =~ "implementation file, call site, or focused test"
  end

  test "search_tuist_code returns revisioned matches and truncation metadata" do
    arguments = %{"pattern" => "cache", "path" => "server", "max_results" => 2}

    expect(CodebaseSearch, :search, fn ^arguments ->
      {:ok,
       %{
         "revision" => "abc123",
         "query" => "cache",
         "matches" => [
           %{
             "path" => "server/lib/cache.ex",
             "line_number" => 12,
             "line" => "def cache do",
             "context_before" => [],
             "context_after" => ["end"],
             "url" => "https://github.com/tuist/tuist/blob/abc123/server/lib/cache.ex#L12"
           }
         ],
         "truncated" => true,
         "truncation_reason" => "file_limit",
         "stats" => search_stats()
       }}
    end)

    result = SearchTuistCode.call(%Plug.Conn{}, arguments)

    assert %{
             "structuredContent" => %{
               "revision" => "abc123",
               "truncated" => true,
               "truncation_reason" => "file_limit"
             }
           } = result
  end

  test "list_tuist_files returns bounded entries" do
    arguments = %{"path" => "server/lib", "depth" => 1}

    expect(CodebaseSearch, :list_files, fn ^arguments ->
      {:ok,
       %{
         "revision" => "abc123",
         "entries" => [
           %{
             "path" => "server/lib/tuist",
             "type" => "directory",
             "url" => "https://github.com/tuist/tuist/tree/abc123/server/lib/tuist"
           }
         ],
         "truncated" => false,
         "truncation_reason" => nil,
         "stats" => %{"entries_visited" => 2, "walk_errors" => 0, "elapsed_milliseconds" => 1}
       }}
    end)

    assert %{"structuredContent" => %{"entries" => [%{"type" => "directory"}]}} =
             ListTuistFiles.call(%Plug.Conn{}, arguments)
  end

  test "read_tuist_file returns bounded source lines and a continuation" do
    arguments = %{"path" => "server/lib/cache.ex", "start_line" => 10, "max_lines" => 2}

    expect(CodebaseSearch, :read_file, fn ^arguments ->
      {:ok,
       %{
         "revision" => "abc123",
         "path" => "server/lib/cache.ex",
         "start_line" => 10,
         "end_line" => 11,
         "lines" => [%{"number" => 10, "text" => "def cache do"}],
         "file_size_bytes" => 1_024,
         "truncated" => true,
         "truncation_reason" => "line_limit",
         "next_start_line" => 12,
         "url" => "https://github.com/tuist/tuist/blob/abc123/server/lib/cache.ex#L10-L11",
         "elapsed_milliseconds" => 1
       }}
    end)

    assert %{
             "structuredContent" => %{
               "next_start_line" => 12,
               "lines" => [%{"number" => 10}]
             }
           } = ReadTuistFile.call(%Plug.Conn{}, arguments)
  end

  defp search_stats do
    %{
      "files_scanned" => 20_000,
      "bytes_scanned" => 1_024,
      "context_bytes_read" => 128,
      "files_skipped_too_large" => 0,
      "contexts_skipped" => 0,
      "file_errors" => 0,
      "walk_errors" => 0,
      "elapsed_milliseconds" => 4_000
    }
  end
end
