defmodule Tuist.ApplicationTest do
  use ExUnit.Case, async: true

  test "feature-flag notifications start under Tuist after PubSub is available" do
    included = Application.spec(:tuist, :included_applications)
    assert :fun_with_flags in included
    assert :fun_with_flags_ui in included

    children = Supervisor.which_children(Tuist.Supervisor)

    assert {FunWithFlags.Supervisor, Process.whereis(FunWithFlags.Supervisor), :supervisor, [FunWithFlags.Supervisor]} in children

    assert FunWithFlags.Notifications.PhoenixPubSub.subscribed?()
  end
end
