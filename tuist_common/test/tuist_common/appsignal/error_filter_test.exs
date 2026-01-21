defmodule TuistCommon.Appsignal.ErrorFilterTest do
  use ExUnit.Case, async: true

  alias TuistCommon.Appsignal.ErrorFilter

  describe "filter/2" do
    test "ignores all log events (no filtering needed with modified Bandit)" do
      # With the modified Bandit, client disconnects during body reads now raise
      # Bandit.TransportError (ignored via AppSignal config) instead of HTTPError.
      # This filter no longer needs to filter anything.
      log_event = %{
        meta: %{
          crash_reason: {
            %Bandit.HTTPError{message: "Body read timeout", plug_status: 408},
            []
          }
        }
      }

      assert ErrorFilter.filter(log_event, []) == :ignore
    end

    test "ignores log events without crash_reason in meta" do
      log_event = %{
        meta: %{
          some_other_key: "value"
        }
      }

      assert ErrorFilter.filter(log_event, []) == :ignore
    end

    test "ignores log events with empty meta" do
      log_event = %{meta: %{}}

      assert ErrorFilter.filter(log_event, []) == :ignore
    end

    test "ignores arbitrary log events" do
      assert ErrorFilter.filter(%{level: :info, msg: "hello"}, []) == :ignore
      assert ErrorFilter.filter(:some_atom, []) == :ignore
      assert ErrorFilter.filter(nil, []) == :ignore
    end
  end
end
