defmodule Symptoms.LogTest do
  use ExUnit.Case, async: true

  alias Symptoms.Log

  test "fit trims an oversized entity key to an identifiable prefix and hash" do
    # A 20 000-byte key alone is over the 16 384-byte cap.
    key = "GET /" <> String.duplicate("a", 19_995)
    document = %{"entity" => %{"service" => "s", "kind" => "route", "key" => key}, "title" => "t"}

    fitted = Log.fit(document)
    assert byte_size(Jason.encode!(fitted)) <= Log.max_bytes()

    # The first 200 characters (bytes, for this ASCII key), then "…sha256:" and the key's full hex digest, so
    # two long keys with the same prefix stay distinct.
    digest = :sha256 |> :crypto.hash(key) |> Base.encode16(case: :lower)
    assert fitted["entity"]["key"] == binary_part(key, 0, 200) <> "…sha256:" <> digest
    assert Log.fit(%{"entity" => %{"key" => "GET /short"}}) == %{"entity" => %{"key" => "GET /short"}}
  end
end
