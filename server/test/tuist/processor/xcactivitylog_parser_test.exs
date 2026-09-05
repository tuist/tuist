defmodule Tuist.Processor.XCActivityLogParserTest do
  # Writes a stub executable into the app's priv dir, which is global state.
  use ExUnit.Case, async: false

  alias Tuist.Processor.XCActivityLogParser

  @executable_path Path.join([:code.priv_dir(:tuist), "native", "xcactivitylog-parser"])

  defp install_parser(script) do
    File.mkdir_p!(Path.dirname(@executable_path))
    File.write!(@executable_path, "#!/bin/sh\n" <> script)
    File.chmod!(@executable_path, 0o755)
    on_exit(fn -> File.rm(@executable_path) end)
  end

  defp parse do
    XCActivityLogParser.parse("log.xcactivitylog", "cas.db", "cas_metadata", false)
  end

  test "returns the decoded build data the parser wrote" do
    install_parser(~S|printf '{"status":"success","targets":[]}' > "$4"|)

    assert {:ok, %{"status" => "success", "targets" => []}} = parse()
  end

  test "returns an error when the parser is not built" do
    File.rm(@executable_path)

    assert {:error, {:parser_not_found, @executable_path}} = parse()
  end

  test "returns the parser's own message when it exits with a handled error" do
    install_parser(~S|echo "unsupported log version" >&2; exit 1|)

    assert {:error, "unsupported log version"} = parse()
  end

  # The reason this module shells out at all: a Swift runtime trap aborts the
  # parser process, and that has to surface as an error rather than take the
  # BEAM down with it.
  test "returns a crash error when the parser dies on a signal" do
    install_parser(~S|kill -s ILL $$|)

    assert {:error, {:parser_crashed, 132, _output}} = parse()
  end

  test "leaves no output file behind" do
    install_parser(~S|printf '{"status":"success"}' > "$4"|)
    before = leftover_output_files()

    assert {:ok, _} = parse()

    assert leftover_output_files() == before
  end

  defp leftover_output_files do
    [System.tmp_dir!(), "xcactivitylog_*.json"] |> Path.join() |> Path.wildcard() |> Enum.sort()
  end
end
