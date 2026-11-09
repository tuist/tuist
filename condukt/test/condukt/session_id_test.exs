defmodule Condukt.SessionIDTest do
  use ExUnit.Case, async: true

  alias Condukt.SessionID

  @uuidv7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "generates a canonical UUIDv7 string" do
    id = SessionID.generate()

    assert is_binary(id)
    assert id =~ @uuidv7_regex
  end

  test "successive ids are unique" do
    ids = for _ <- 1..1_000, do: SessionID.generate()

    assert length(Enum.uniq(ids)) == length(ids)
  end

  test "ids generated in different milliseconds sort lexicographically" do
    earlier = SessionID.generate()
    Process.sleep(5)
    later = SessionID.generate()

    assert earlier < later
  end
end
