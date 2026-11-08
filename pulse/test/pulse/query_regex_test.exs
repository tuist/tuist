defmodule Pulse.QueryRegexTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Codec.NIF
  alias Pulse.LogQL.Evaluator
  alias Pulse.LogQL.{Parser, QueryValidation}
  alias Pulse.LogQL.StreamMatchers
  alias Pulse.Loki.Tail
  alias Pulse.Record.Log

  @controls Path.expand("../fixtures/regex/go-controls.json", __DIR__)
  @external_resource @controls
  @admission Path.expand("../fixtures/regex/admission-controls.json", __DIR__)
  @external_resource @admission
  @classes Path.expand("../fixtures/regex/class-controls.json", __DIR__)
  @external_resource @classes
  @ranges Path.expand("../fixtures/regex/range-controls.json", __DIR__)
  @external_resource @ranges
  @names Path.expand("../fixtures/regex/name-controls.json", __DIR__)
  @external_resource @names
  @flags Path.expand("../fixtures/regex/flag-controls.json", __DIR__)
  @external_resource @flags
  @unicode Path.expand("../fixtures/regex/unicode-controls.json", __DIR__)
  @external_resource @unicode
  @erased Path.expand("../fixtures/regex/erased-capture-controls.json", __DIR__)
  @external_resource @erased
  @nested Path.expand("../fixtures/regex/nested-repetition-controls.json", __DIR__)
  @external_resource @nested
  @selector_names Path.expand("../fixtures/regex/selector-name-controls.json", __DIR__)
  @external_resource @selector_names
  @properties Path.expand("../fixtures/regex/unicode-property-controls.json", __DIR__)
  @external_resource @properties
  @scalar_complements Path.expand("../fixtures/regex/scalar-complement-controls.json", __DIR__)
  @external_resource @scalar_complements

  # This bounded corpus checks over 54,000 inputs through several native APIs;
  # allow for dirty-scheduler contention during the full concurrent CI suite.
  @tag timeout: 180_000
  test "Unicode properties and scalar class complements match the pinned upstream engine" do
    for path <- [@scalar_complements, @properties],
        row <- path |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases") do
      pattern = row["pattern"]

      if row["valid"] do
        assert {:ok, regex} = NIF.compile_log_regex(pattern), pattern
        assert {:ok, full} = NIF.compile_metric_capture_regex(pattern), pattern

        for value <- row["values"] do
          input = value["text"]
          assert NIF.match_log_regex(regex, input) == value["match"], inspect({pattern, input})
          captures = NIF.metric_regex_captures(full, input)
          assert captures != nil == value["label_match"], inspect({pattern, input})
          if Map.has_key?(value, "captures"), do: assert(captures == value["captures"], inspect({pattern, input}))

          if Map.has_key?(value, "named_captures"),
            do: assert(NIF.log_regex_named_captures(regex, input) == value["named_captures"], inspect({pattern, input}))

          if Map.has_key?(value, "count") do
            assert {:ok, count} = NIF.log_regex_count(pattern, input, value["count"] + 1)
            assert count == value["count"], inspect({pattern, input})

            for {literal?, key} <- [{false, "replacement"}, {true, "literal_replacement"}] do
              assert {:ok, result, _work} =
                       NIF.log_regex_replace(pattern, input, "<$0:${piece}:${tail}>", literal?, 100_000, 1_000_000)

              assert result == value[key], inspect({pattern, input})
            end
          end
        end
      else
        assert :error = NIF.compile_log_regex(pattern), pattern
        assert :error = NIF.validate_metric_regex(pattern), pattern
        assert :error = NIF.compile_metric_capture_regex(pattern), pattern
      end
    end
  end

  test "Unicode property expansion is bounded even when repetitions erase the program" do
    pattern = ~S/\p{L}{0}/
    assert {:ok, _} = NIF.compile_log_regex(String.duplicate(pattern, 8))

    for oversized <- [String.duplicate(pattern, 200), "[" <> String.duplicate(~S/\p{L}/, 200) <> "]{0}"] do
      assert :error = NIF.compile_log_regex(oversized)
      assert :error = NIF.compile_metric_capture_regex(oversized)
      assert :error = NIF.validate_metric_regex(oversized)
      assert :error = NIF.log_regex_count(oversized, "", 2)
      assert :error = NIF.log_regex_replace(oversized, "", "$0", false, 100, 100)
    end
  end

  test "independent PCRE and native byte engines replay actual Go answers" do
    for row <- @controls |> File.read!() |> Pulse.JSON.decode!() do
      %{"pattern" => pattern, "value" => value, "match" => expected} = row
      assert {:ok, reference} = Pulse.QueryRegex.compile(pattern)
      assert Regex.match?(reference, value) == expected, inspect(row)
      assert {:ok, native} = NIF.compile_log_regex(pattern)
      assert NIF.filter_log_regex(native, [{:kept, value}], false) == if(expected, do: [:kept], else: []), inspect(row)

      if Map.has_key?(row, "label_match") do
        anchored = StreamMatchers.anchor(pattern)
        assert {:ok, reference} = Pulse.QueryRegex.compile(anchored)
        assert Regex.match?(reference, value) == row["label_match"], inspect(row)
        assert NIF.match_metric_regex(anchored, value) == row["label_match"], inspect(row)
      end
    end
  end

  # About 67,000 dirty-CPU NIF calls. Alone this takes ~2 s, but every call
  # queues behind concurrent tests' native work: with CI's concurrency it took
  # 75 s, past ExUnit's 60 s default. The corpus is fixed, so this stays bounded.
  @tag timeout: 300_000
  test "repetition, class and raw-header admission replay actual Go answers" do
    for path <- [@admission, @classes, @ranges, @names, @flags, @unicode, @erased, @nested, @selector_names],
        row <- path |> File.read!() |> Pulse.JSON.decode!() |> Map.fetch!("cases") do
      pattern = row["pattern"]

      if row["valid"] do
        assert {:ok, native} = NIF.compile_log_regex(pattern), pattern
        assert {:ok, full} = NIF.compile_metric_capture_regex(pattern), pattern
        assert {:ok, predicate} = NIF.compile_log_regex(StreamMatchers.anchor(pattern)), pattern
        assert {:ok, reference} = Pulse.QueryRegex.compile(Map.get(row, "reference_pattern", pattern)), pattern

        for value <- row["values"] do
          input = String.duplicate(value["text"], value["repeat"])
          assert Regex.match?(reference, input) == value["match"], inspect({pattern, value})

          assert NIF.filter_log_regex(native, [{:kept, input}], false) != [] == value["match"],
                 inspect({pattern, value})

          captures = NIF.metric_regex_captures(full, input)
          assert NIF.match_log_regex(predicate, input) == value["label_match"], inspect({pattern, value})
          assert captures != nil == value["label_match"], inspect({pattern, value})
          if Map.has_key?(value, "captures"), do: assert(captures == value["captures"], inspect({pattern, value}))

          if Map.has_key?(value, "named_captures"),
            do:
              assert(NIF.log_regex_named_captures(native, input) == value["named_captures"], inspect({pattern, value}))

          if Map.has_key?(value, "count") do
            assert {:ok, count} = NIF.log_regex_count(pattern, input, value["count"] + 1)
            assert count == value["count"], inspect({pattern, value})
            assert {:error, :query_work_limit} = NIF.log_regex_count(pattern, input, value["count"])

            for {literal?, key} <- [{false, "replacement"}, {true, "literal_replacement"}] do
              assert {:ok, result, _work} =
                       NIF.log_regex_replace(pattern, input, "<$0:${piece}:${tail}>", literal?, 100_000, 1_000_000)

              assert result == value[key], inspect({pattern, value})
            end
          end
        end
      else
        assert :error = NIF.compile_log_regex(pattern), pattern
        assert :error = NIF.validate_metric_regex(pattern), pattern
        assert :error = NIF.compile_metric_capture_regex(pattern), pattern
      end
    end
  end

  test "selector names retain regexp parser uniqueness and numeric tail-label ownership" do
    fixture = @selector_names |> File.read!() |> Pulse.JSON.decode!()

    for row <- fixture["cases"], row["valid"] do
      pattern = row["pattern"]
      assert {:ok, native} = NIF.compile_log_regex(pattern)
      assert NIF.log_regex_named_capture?(native) == row["parser_valid"], pattern
      assert {:ok, ast} = Parser.parse(~s({job="names"} | regexp ) <> Pulse.JSON.encode!(pattern))
      assert QueryValidation.validate(ast) == :ok == row["parser_valid"], pattern

      if row["parser_valid"] do
        compiled = Tail.compile(ast)

        for value <- row["values"] do
          record = %Log{timestamp_ns: 1, body: value["text"], resource: %{"job" => "names"}}
          expected = Map.put(value["named_captures"] || %{}, "job", "names")
          assert [%{labels: ^expected}] = Tail.select(compiled, [record]), inspect({pattern, value})
        end
      end
    end
  end

  test "adversarial backtracking shapes agree before and after parsing, in tails and Parquet" do
    pattern = "^(?:(a|aa)+b|a+c)$"
    line = String.duplicate("a", 64) <> "c"
    record = %Log{timestamp_ns: 1, service: "api", body: line, resource: %{"x" => line}}
    assert :ok = Pulse.Storage.append(:logs, "regex-runtime", [record])
    assert {:ok, blob, _, _, _} = NIF.encode_log_segment_parquet([record])
    assert {:ok, [^record]} = NIF.decode_log_segment_parquet(blob, nil, nil, nil, [], [{:match_re, pattern}])
    quoted = Pulse.JSON.encode!(pattern)

    for {suffix, matches?} <- [
          {" |~ " <> quoted, true},
          {" | json |~ " <> quoted, true},
          {" | json !~ " <> quoted, false},
          {" | x=~" <> quoted, true},
          {" | x!~" <> quoted, false},
          {" | drop x=~" <> quoted <> " | x=\"\"", true},
          {" | keep x=~" <> quoted <> " | x!=\"\"", true}
        ] do
      assert {:ok, ast} = Parser.parse(~s({service="api"}) <> suffix)
      assert :ok = QueryValidation.validate(ast)
      assert {:ok, streams} = Evaluator.evaluate_log(ast, "regex-runtime", %{})
      assert streams != [] == matches?, suffix
      assert Tail.select(Tail.compile(ast), [record]) != [] == matches?, suffix
    end
  end

  test "native named captures retain unmatched groups and do not conceal a PCRE execution limit" do
    line = String.duplicate("a", 64) <> "c"
    pattern = "^(?:(?<first>a|aa)+b|(?<kept>a+c))$"
    assert {:ok, native} = NIF.compile_log_regex(pattern)
    assert %{"first" => "", "kept" => ^line} = NIF.log_regex_named_captures(native, line)
    assert nil == NIF.log_regex_named_captures(native, "unmatched")

    record = %Log{timestamp_ns: 1, service: "api", body: line}
    query = ~s({service="api"} | regexp ) <> Pulse.JSON.encode!(pattern) <> ~s( | kept!="")
    assert {:ok, ast} = Parser.parse(query)
    assert :ok = QueryValidation.validate(ast)

    assert [%{labels: %{"kept" => ^line, "first" => ""}}] =
             Tail.select(Tail.compile(ast), [record])
  end

  test "erased captures keep empty-label ownership across parser stages and tails" do
    record = %Log{timestamp_ns: 1, body: "c", resource: %{"app" => "api"}}
    assert :ok = Pulse.Storage.append(:logs, "erased-captures", [record])

    for prefix <- ["", ~s' | regexp "(?P<gone>c)"'],
        {filter, labels} <- [
          {~s(gone=""), %{"app" => "api", "gone" => "", "kept" => "c"}},
          {~s(gone="c"), %{"app" => "api", "gone" => "c", "kept" => "c"}}
        ] do
      query =
        ~s({app="api"}) <>
          prefix <>
          ~s' | regexp "(?P<gone>x){0}(?P<kept>c)" | regexp "(?P<gone>c)" | ' <> filter

      assert {:ok, ast} = Parser.parse(query)
      assert :ok = QueryValidation.validate(ast)
      expected = if prefix == "" == (filter == ~s(gone="")), do: [labels], else: []
      assert {:ok, streams} = Evaluator.evaluate_log(ast, "erased-captures", %{})
      assert Enum.map(streams, &elem(&1, 0)) == expected
      assert Enum.map(Tail.select(Tail.compile(ast), [record]), & &1.labels) == expected
    end
  end

  test "original capture schemas stay bounded when every group is optimized away" do
    # The 1 MiB schema ceiling charges 32 bytes per original group, even if
    # the resulting program is just an empty match with no native captures.
    pattern = String.duplicate("(){0}", 32_768)
    name = String.duplicate("a", 1_048_544)

    for {allowed, oversized} <- [
          {pattern, pattern <> "(){0}"},
          {"(?P<#{name}>x){0}", "(?P<#{name}a>x){0}"}
        ] do
      assert {:ok, _} = NIF.compile_log_regex(allowed)
      assert {:ok, _} = NIF.compile_metric_capture_regex(allowed)
      assert :ok = NIF.validate_metric_regex(allowed)
      assert {:ok, 1} = NIF.log_regex_count(allowed, "", 2)
      assert :error = NIF.compile_log_regex(oversized)
      assert :error = NIF.compile_metric_capture_regex(oversized)
      assert :error = NIF.validate_metric_regex(oversized)
      assert :error = NIF.log_regex_count(oversized, "", 2)
      assert :error = NIF.log_regex_replace(oversized, "", "$0", false, 100, 100)
    end
  end

  test "all pipeline regex positions reject unsupported patterns and quoted repairs" do
    for pattern <- [
          ~S"[\Qx\E]",
          ~S"\Q\E*",
          ~S"\1",
          ~S"\8",
          ~S"\E",
          "a{2}{3}",
          "a*{2}",
          "a+{2}",
          "a?{1}",
          ~S"\x{}",
          ~S"\x{61",
          ~S"\x{110000}",
          ~S"\x{zz}",
          ~S"\x{61}{2}+",
          ~S"\x{61}*{2}",
          ~S"\\x{2}+",
          "a???",
          "a{2}??",
          ~S"\x{61}{2}??",
          ~S"\x{61}???",
          ~S"\x{61}+??",
          ~S"\x{61}*??"
        ],
        stage <- ["|~ ", "| x=~", "| drop x=~", "| keep x=~", "| regexp "] do
      assert :error = NIF.compile_log_regex(pattern)
      query = ~s({service="api"} ) <> stage <> Pulse.JSON.encode!(pattern)
      assert {:ok, ast} = Parser.parse(query)
      assert {:error, {:invalid_regex, _, _, _}} = QueryValidation.validate(ast), query
    end
  end

  @tag :template_count_batch
  @tag :template_regex_replace_batch
  test "native regex counts and replacements agree with an independent Elixir iterator" do
    :rand.seed(:exsss, {127, 391, 823})
    alphabet = ["a", "b", "1", "_", "é", "🙂", "\n", "\v", " "]

    inputs =
      ["", "a", "aa", "aba", "é🙂"] ++
        for _ <- 1..64,
            do: Enum.map_join(1..:rand.uniform(13), fn _ -> Enum.at(alphabet, :rand.uniform(length(alphabet)) - 1) end)

    for pattern <- [
          "a",
          "aa",
          "a|ab",
          "ab|a",
          "a*",
          "a*?",
          "(?:a?)*",
          "",
          ".",
          "(?s).",
          "^",
          "$",
          "[ab]",
          "[^ab]",
          ~S"\b",
          ~S"\B",
          ~S"\d",
          ~S"\D",
          ~S"\w",
          ~S"\s"
        ],
        input <- inputs do
      assert {:ok, regex} = Pulse.QueryRegex.compile(pattern)
      expected = reference_count(regex, input, 0, -1)
      assert {:ok, ^expected} = NIF.log_regex_count(pattern, input, expected + 1), inspect({pattern, input})
      assert {:error, :query_work_limit} = NIF.log_regex_count(pattern, input, expected)

      for literal? <- [false, true] do
        expected = reference_replacement(regex, input, literal?, 0, -1, [])
        assert {:ok, ^expected, _work} = NIF.log_regex_replace(pattern, input, "[$0]$$", literal?, 100_000, 4096)
      end
    end

    # Two passes each spend two match probes, one EOF probe and two capture
    # expansions: exactly ten units, independently of the returned work value.
    assert {:ok, "aa", 10} = NIF.log_regex_replace("a", "aa", "${0}", false, 10, 2)
    assert {:error, :query_work_limit} = NIF.log_regex_replace("a", "aa", "${0}", false, 9, 2)
    assert {:error, :query_work_limit} = NIF.log_regex_replace("a", "aa", "x", true, 0, 2)
  end

  defp reference_replacement(_regex, input, _literal?, position, previous, parts) when position > byte_size(input) do
    tail = binary_part(input, max(0, previous), byte_size(input) - max(0, previous))
    [tail | parts] |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp reference_replacement(regex, input, literal?, position, previous, parts) do
    case Regex.run(regex, input, offset: position, return: :index, capture: :first) do
      nil ->
        reference_replacement(regex, input, literal?, byte_size(input) + 1, previous, parts)

      [{start, length}] ->
        finish = start + length
        position = if length == 0, do: advance_codepoint(input, finish), else: finish
        replacement = if literal?, do: "[$0]$$", else: "[" <> binary_part(input, start, length) <> "]$"

        parts =
          if length == 0 and start == previous do
            parts
          else
            unmatched = binary_part(input, max(0, previous), start - max(0, previous))
            [replacement, unmatched | parts]
          end

        reference_replacement(regex, input, literal?, position, finish, parts)
    end
  end

  defp reference_count(_regex, input, position, _previous) when position > byte_size(input), do: 0

  defp reference_count(regex, input, position, previous) do
    case Regex.run(regex, input, offset: position, return: :index, capture: :first) do
      nil ->
        0

      [{start, length}] ->
        finish = start + length
        increment = if length == 0 and start == previous, do: 0, else: 1
        position = if length == 0, do: advance_codepoint(input, finish), else: finish
        increment + reference_count(regex, input, position, finish)
    end
  end

  defp advance_codepoint(input, position) when position == byte_size(input), do: position + 1

  defp advance_codepoint(input, position) do
    {_, rest} = String.next_codepoint(binary_part(input, position, byte_size(input) - position))
    byte_size(input) - byte_size(rest)
  end
end
