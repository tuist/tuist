defmodule Condukt.Sandbox.NetworkPolicy.K8s.PortForwardTest do
  use ExUnit.Case, async: true

  alias Condukt.Sandbox.NetworkPolicy.K8s.PortForward

  # Regression coverage for the dropped-handshake / off-by-two strip
  # bug: the API server ships the port-forward channel handshake bytes
  # in the same read as the HTTP 101, so they arrive as `:data` parts
  # during the upgrade. The old accumulator used Map.merge and
  # overwrote `:data`; any dropped byte made the codec eat two real
  # bytes off the first data/error frame. The accumulator must
  # concatenate every `:data` part in order, across parts and recv
  # iterations.
  describe "__merge_upgrade_parts__/3" do
    setup do
      %{ref: make_ref(), acc: PortForward.__upgrade_acc__()}
    end

    test "collects status, headers and done for the matching ref", %{ref: ref, acc: acc} do
      acc =
        PortForward.__merge_upgrade_parts__(
          acc,
          [{:status, ref, 101}, {:headers, ref, [{"upgrade", "websocket"}]}, {:done, ref}],
          ref
        )

      assert acc.status == 101
      assert acc.headers == [{"upgrade", "websocket"}]
      assert acc.done == true
    end

    test "concatenates data parts in order rather than overwriting", %{ref: ref, acc: acc} do
      acc =
        PortForward.__merge_upgrade_parts__(
          acc,
          [{:data, ref, <<0, 154, 58>>}, {:data, ref, <<1, 154, 58>>}],
          ref
        )

      assert acc.data == <<0, 154, 58, 1, 154, 58>>
    end

    test "preserves data accumulated across recv iterations", %{ref: ref, acc: acc} do
      acc = PortForward.__merge_upgrade_parts__(acc, [{:data, ref, <<0, 154, 58>>}], ref)
      acc = PortForward.__merge_upgrade_parts__(acc, [{:data, ref, ~s({"type":"event"})}], ref)

      assert acc.data == <<0, 154, 58>> <> ~s({"type":"event"})
    end

    test "ignores parts addressed to a different request ref", %{ref: ref, acc: acc} do
      other = make_ref()

      result =
        PortForward.__merge_upgrade_parts__(
          acc,
          [{:status, other, 500}, {:data, other, "stray"}, {:done, other}],
          ref
        )

      assert result == acc
    end
  end
end
