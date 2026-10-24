defmodule TuistWeb.DrainingTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Tuist.Application.EndpointDrainer
  alias TuistWeb.Draining

  setup do
    on_exit(fn -> :persistent_term.erase(Draining) end)
    file = Path.join(System.tmp_dir!(), "tuist-draining-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(file) end)
    %{drain_file: file}
  end

  test "the server is not draining when it starts" do
    refute Draining.draining?()
  end

  test "the server drains once the preStop hook creates the file", %{drain_file: file} do
    start_supervised!({Draining, file: file, interval: 10, name: :draining_test_watcher})
    Process.sleep(50)
    refute Draining.draining?()

    File.touch!(file)

    assert eventually(&Draining.draining?/0)
  end

  test "a draining server keeps draining after the file disappears", %{drain_file: file} do
    File.touch!(file)
    start_supervised!({Draining, file: file, interval: 10, name: :draining_test_watcher})
    assert eventually(&Draining.draining?/0)

    File.rm!(file)
    Process.sleep(50)

    assert Draining.draining?()
  end

  test "prep_stop drains before it stops the endpoint" do
    test_process = self()
    stub(EndpointDrainer, :drain, fn endpoint -> send(test_process, {:drained, endpoint, Draining.draining?()}) end)

    assert Tuist.Application.prep_stop(:state) == :state

    assert_received {:drained, TuistWeb.Endpoint, true}
  end

  defp eventually(check, attempts \\ 100) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
