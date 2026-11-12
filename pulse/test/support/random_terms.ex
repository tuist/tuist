defmodule Pulse.Test.RandomTerms do
  @moduledoc """
  Random data for equivalence tests between the Rust codecs and their
  Elixir reference implementations. Uses `:rand`, which ExUnit seeds per
  test from the run's `--seed`, so failures reproduce.
  """

  import Bitwise

  alias Pulse.Record.Log

  @atom_keys [:a1, :a2, :a3, :a4, :a5, :a6]

  @chars [?a, ?z, ?A, ?0, ?9, ?\s, ?", ?\\, ?/, ?\n, ?\t, ?\r, 0, 1, 0x1F, 0x7F]
  @multibyte ["é", "ß", "中", "😀", <<0xE2, 0x80, 0xA8>>]

  def string do
    case :rand.uniform(10) do
      1 -> ""
      2 -> String.duplicate("x", 60 + :rand.uniform(200))
      _ -> for(_ <- 1..:rand.uniform(24), into: "", do: char())
    end
  end

  defp char do
    if :rand.uniform(4) == 1, do: Enum.random(@multibyte), else: <<Enum.random(@chars)>>
  end

  def integer do
    case :rand.uniform(6) do
      1 -> :rand.uniform(1 <<< 63) - 1
      2 -> -:rand.uniform(1 <<< 63)
      3 -> (1 <<< 63) + :rand.uniform((1 <<< 63) - 1)
      _ -> :rand.uniform(2000) - 1000
    end
  end

  def float do
    case :rand.uniform(4) do
      1 -> :rand.uniform() * :math.pow(10, :rand.uniform(300))
      2 -> -:rand.uniform() / :math.pow(10, :rand.uniform(300))
      3 -> Enum.random([0.0, -0.0, 1.0, 0.1, 1.0e20, 2.5e-7])
      _ -> :rand.uniform() * 1000
    end
  end

  @doc "A value `JSON.decode/1` could return: string keys only."
  def json(depth \\ 3) do
    scalars = [&string/0, &integer/0, &float/0, fn -> Enum.random([true, false, nil]) end]

    containers = [
      fn -> for _ <- 1..:rand.uniform(5), do: json(depth - 1) end,
      fn -> for _ <- 1..:rand.uniform(5), into: %{}, do: {string(), json(depth - 1)} end
    ]

    generators = if depth > 0, do: scalars ++ scalars ++ containers, else: scalars
    Enum.random(generators).()
  end

  @doc """
  A term `JSON.encode!/1` accepts that the Rust encoder also handles:
  binary, atom and integer keys (never colliding once stringified), other
  atoms as values, charlists.
  """
  def encodable(depth \\ 3) do
    case :rand.uniform(if depth > 0, do: 10, else: 7) do
      5 -> Enum.random([:ok, :some_atom, :"with space"])
      6 -> ~c"charlist"
      8 -> for _ <- 1..:rand.uniform(5), do: encodable(depth - 1)
      9 -> map_with_mixed_keys(depth)
      10 -> map_with_mixed_keys(depth)
      _ -> json(0)
    end
  end

  def map_with_mixed_keys(depth) do
    for i <- 1..:rand.uniform(6), into: %{} do
      key =
        case :rand.uniform(3) do
          1 -> "k#{i}-" <> string()
          2 -> Enum.at(@atom_keys, i - 1)
          3 -> 1_000_000 + i
        end

      {key, encodable(depth - 1)}
    end
  end

  @doc "Log records shaped like the decoders produce, with shared resources."
  def logs(n) do
    resources = for s <- 1..3, do: %{"service_name" => "svc#{s}", "pod" => string(), "zone" => "eu-#{s}"}

    for _ <- 1..n do
      %Log{
        timestamp_ns: Enum.random([nil | List.duplicate(:rand.uniform(1 <<< 62), 8)]),
        observed_timestamp_ns: Enum.random([nil, :rand.uniform(1 <<< 62)]),
        severity_number: Enum.random([nil, 9, 17]),
        severity_text: Enum.random([nil, "info", "warn", string()]),
        service: Enum.random([nil, "svc1", "svc2", "svc3"]),
        body: Enum.random([string(), string(), integer(), [1, "two"], %{"k" => string()}]),
        trace_id: Enum.random([nil, Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)]),
        span_id: Enum.random([nil, Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)]),
        attributes: Enum.random([%{}, nil, map_with_mixed_keys(2), %{"user" => string()}]),
        resource: Enum.random([nil | resources])
      }
    end
  end
end
