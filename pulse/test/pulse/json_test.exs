defmodule Pulse.JSONTest do
  # Pulse.JSON must behave exactly like Elixir's JSON: same values, same
  # errors. These tests compare the two on random and edge-case input, and
  # also assert the Rust path actually answered (so equivalence is not
  # just the fallback agreeing with itself).
  use Pulse.Test.Case, async: true

  import Bitwise

  alias Pulse.Codec.NIF
  alias Pulse.Record.Log
  alias Pulse.Test.RandomTerms

  test "projected tuple keys and values detach slices without copying standalone binaries" do
    arena = String.duplicate("x", 1024 * 1024)
    slice = binary_part(arena, 1, 100)
    standalone = :binary.copy(slice)
    assert :binary.referenced_byte_size(slice) > byte_size(slice)
    {key, %{value: value, standalone: kept}} = Pulse.JSON.detach({{slice}, %{value: slice, standalone: standalone}})
    assert elem(key, 0) == value
    assert :binary.referenced_byte_size(elem(key, 0)) == 100
    assert :binary.referenced_byte_size(value) == 100
    assert :erts_debug.same(kept, standalone)
    assert %Log{body: detached} = Pulse.JSON.detach(%Log{body: slice})
    assert :binary.referenced_byte_size(detached) == 100
  end

  @backslash <<92>>

  defp same_decode(doc) do
    assert Pulse.JSON.decode(doc) == JSON.decode(doc), "decode differs for #{inspect(doc)}"
  end

  defp roundtrip(term), do: term |> Pulse.JSON.encode!() |> JSON.decode!()

  defp error_kind(error) when is_exception(error), do: error.__struct__
  defp error_kind(error), do: error

  describe "decode" do
    test "matches JSON.decode/1 on random documents, via Rust" do
      for _ <- 1..500 do
        value = RandomTerms.json()
        doc = JSON.encode!(value)
        assert {:ok, _} = NIF.json_decode(doc)
        same_decode(doc)
        same_decode(" \n\t" <> doc <> "\r\n ")
      end
    end

    test "matches JSON.decode/1 on edge cases, including every error" do
      u = fn hex -> @backslash <> "u" <> hex end

      docs = [
        ~s({"a":1,"a":2}),
        "123456789012345678901234567890",
        "-123456789012345678901234567890",
        "18446744073709551615",
        "18446744073709551616",
        "-9223372036854775808",
        "-9223372036854775809",
        "-0",
        "-0.0",
        "1E2",
        "1e400",
        "1e-400",
        "5e-324",
        "2.2250738585072014e-308",
        "01",
        "1.",
        ".5",
        "+1",
        "[1,]",
        ~s({"a":1,}),
        "",
        "   ",
        "nul",
        "1 2",
        "\"" <> u.("d800") <> "\"",
        "\"" <> u.("dc00") <> "\"",
        "\"" <> u.("d83d") <> u.("de00") <> "\"",
        "\"" <> u.("0000") <> u.("00e9") <> "\"",
        "\"a" <> @backslash <> "/b\"",
        "\"" <> @backslash <> "x41\"",
        <<?", 1, ?">>,
        <<?", 0xFF, ?">>,
        String.duplicate("[", 300) <> String.duplicate("]", 300),
        String.duplicate("[", 10_000) <> String.duplicate("]", 10_000)
      ]

      for doc <- docs, do: same_decode(doc)
    end

    test "decode!/1 raises what JSON.decode!/1 raises" do
      for doc <- ["{", "1 2", <<?", 0xFF, ?">>] do
        expected = assert_raise(JSON.DecodeError, fn -> JSON.decode!(doc) end)
        actual = assert_raise(JSON.DecodeError, fn -> Pulse.JSON.decode!(doc) end)
        assert Exception.message(actual) == Exception.message(expected)
      end
    end

    test "large documents take the dirty-scheduler path and still match" do
      value = for i <- 1..5_000, into: %{}, do: {"key-#{i}", String.duplicate("v", 40)}
      doc = JSON.encode!(value)
      assert byte_size(doc) > 64 * 1024
      assert {:ok, _} = NIF.json_decode_dirty(doc)
      same_decode(doc)
    end

    test "long strings are sub-binaries of the input, short ones are copies" do
      long = String.duplicate("x", 200)
      {:ok, %{"long" => l, "short" => s}} = Pulse.JSON.decode(JSON.encode!(%{"long" => long, "short" => "hi"}))
      assert l == long
      assert :binary.referenced_byte_size(l) > byte_size(l)
      assert :binary.referenced_byte_size(s) == byte_size(s)
    end
  end

  describe "encode" do
    test "matches JSON.encode!/1 on random terms, via Rust" do
      for _ <- 1..500 do
        term = RandomTerms.encodable()
        assert {:ok, _} = NIF.json_encode(term, 1 <<< 40)
        assert roundtrip(term) == term |> JSON.encode!() |> JSON.decode!()
      end
    end

    test "matches JSON.encode!/1 byte for byte on strings and integers" do
      for _ <- 1..500 do
        value = Enum.random([RandomTerms.string(), RandomTerms.integer()])
        assert Pulse.JSON.encode!(value) == JSON.encode!(value)
      end
    end

    test "defers to JSON for terms Rust cannot guarantee to match" do
      cases = [
        ~U[2026-01-01 00:00:00Z],
        %{1.5 => 1},
        %{:a => 1, "a" => 2},
        %{1 => :x, "1" => :y},
        123_456_789_012_345_678_901_234_567_890,
        %{"nested" => [%{at: ~D[2026-01-02]}]}
      ]

      for term <- cases do
        assert NIF.json_encode(term, 1 <<< 40) == :fallback
        assert Pulse.JSON.encode!(term) == JSON.encode!(term)
      end
    end

    test "raises what JSON raises on unencodable terms" do
      for term <- [%Log{}, {1, 2}, %{{1} => 2}, [1 | 2], <<0xFF>>, %{"k" => self()}] do
        assert error_kind(catch_error(Pulse.JSON.encode!(term))) == error_kind(catch_error(JSON.encode!(term)))
      end
    end

    test "moves large encodings to a dirty scheduler once past the budget" do
      term = for i <- 1..5_000, do: %{"i" => i, "v" => String.duplicate("v", 40)}
      assert NIF.json_encode(term, 64 * 1024) == :too_big
      assert {:ok, _} = NIF.json_encode_dirty(term)
      assert roundtrip(term) == term
    end

    test "encode_to_iodata!/1 matches encode!/1" do
      term = RandomTerms.encodable()
      assert IO.iodata_to_binary(Pulse.JSON.encode_to_iodata!(term)) == Pulse.JSON.encode!(term)
    end
  end
end
