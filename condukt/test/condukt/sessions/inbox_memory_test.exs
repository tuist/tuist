defmodule Condukt.Sessions.Inbox.MemoryTest do
  use ExUnit.Case, async: true
  use Condukt.Sessions.Inbox.Conformance

  alias Condukt.Sessions.Inbox.Memory

  setup do
    name = :"inbox_#{System.unique_integer([:positive])}"
    start_supervised!({Memory, name: name})
    %{inbox: {Memory, name: name}}
  end
end
