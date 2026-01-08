defmodule TuistCommon.Appsignal.ErrorFilterTest do
  use ExUnit.Case, async: true

  alias TuistCommon.Appsignal.ErrorFilter

  describe "filter/2" do
    test "stops Bandit.HTTPError with 'Body read timeout' message" do
      log_event = %{
        meta: %{
          crash_reason: {
            %Bandit.HTTPError{message: "Body read timeout", plug_status: 408},
            []
          }
        }
      }

      assert ErrorFilter.filter(log_event, []) == :stop
    end

    test "stops Bandit.HTTPError with message containing 'Body read timeout'" do
      log_event = %{
        meta: %{
          crash_reason: {
            %Bandit.HTTPError{message: "Body read timeout after 30s", plug_status: 408},
            [{:some_module, :some_function, 1, []}]
          }
        }
      }

      assert ErrorFilter.filter(log_event, []) == :stop
    end

    test "ignores Bandit.HTTPError with other messages" do
      log_event = %{
        meta: %{
          crash_reason: {
            %Bandit.HTTPError{message: "Connection reset by peer", plug_status: 500},
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

    test "ignores log events with non-Bandit crash reasons" do
      log_event = %{
        meta: %{
          crash_reason: {
            %RuntimeError{message: "some error"},
            []
          }
        }
      }

      assert ErrorFilter.filter(log_event, []) == :ignore
    end

    test "ignores log events with atom crash reasons" do
      log_event = %{
        meta: %{
          crash_reason: {:some_atom, []}
        }
      }

      assert ErrorFilter.filter(log_event, []) == :ignore
    end

    test "ignores arbitrary log events" do
      assert ErrorFilter.filter(%{level: :info, msg: "hello"}, []) == :ignore
      assert ErrorFilter.filter(:some_atom, []) == :ignore
      assert ErrorFilter.filter(nil, []) == :ignore
    end
  end
end
