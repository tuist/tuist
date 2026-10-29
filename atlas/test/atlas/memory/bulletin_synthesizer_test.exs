defmodule Atlas.Memory.BulletinSynthesizerTest do
  use Atlas.DataCase, async: true

  alias Atlas.Memory
  alias Atlas.Memory.BulletinSynthesizer

  describe "bulletin_kinds/0" do
    test "caps the bulletin to durable kinds only" do
      assert BulletinSynthesizer.bulletin_kinds() == [:identity, :decision, :goal]
    end
  end

  describe "bulletin_input_nodes/0" do
    test "includes identities, decisions, and goals" do
      {:ok, identity} =
        Memory.create_node(%{kind: :identity, body: "Pat leads the Acme account."})

      {:ok, decision} =
        Memory.create_node(%{kind: :decision, body: "Adopt RRF for hybrid memory search."})

      {:ok, goal} =
        Memory.create_node(%{kind: :goal, body: "Ship the renewal dashboard by Q3."})

      ids = BulletinSynthesizer.bulletin_input_nodes() |> Enum.map(& &1.id)

      assert identity.id in ids
      assert decision.id in ids
      assert goal.id in ids
    end

    test "excludes ephemeral kinds so they cannot leak into unrelated threads" do
      {:ok, _event} =
        Memory.create_node(%{
          kind: :event,
          body: "Mallorca offsite Aug 31 to Sep 4, villa with jacuzzi."
        })

      {:ok, _fact} =
        Memory.create_node(%{kind: :fact, body: "Acme renewed for one year."})

      {:ok, _observation} =
        Memory.create_node(%{kind: :observation, body: "Support load peaks on Tuesdays."})

      {:ok, _preference} =
        Memory.create_node(%{kind: :preference, body: "Pat prefers Loom over Zoom."})

      {:ok, _todo} =
        Memory.create_node(%{kind: :todo, body: "Follow up with Acme on legal review."})

      bodies = BulletinSynthesizer.bulletin_input_nodes() |> Enum.map(& &1.body)

      refute Enum.any?(bodies, &String.contains?(&1, "Mallorca"))
      refute Enum.any?(bodies, &String.contains?(&1, "Acme renewed"))
      refute Enum.any?(bodies, &String.contains?(&1, "Tuesdays"))
      refute Enum.any?(bodies, &String.contains?(&1, "Loom"))
      refute Enum.any?(bodies, &String.contains?(&1, "legal review"))
    end

    test "excludes pending proposals even when their kind would otherwise feed the bulletin" do
      {:ok, _confirmed} =
        Memory.create_node(%{kind: :identity, body: "Pat leads the Acme account."})

      {:ok, _pending} =
        Memory.create_node(%{
          kind: :identity,
          body: "Unconfirmed identity claim.",
          confirmation: :pending
        })

      bodies = BulletinSynthesizer.bulletin_input_nodes() |> Enum.map(& &1.body)

      assert "Pat leads the Acme account." in bodies
      refute "Unconfirmed identity claim." in bodies
    end

    test "excludes forgotten nodes" do
      {:ok, decision} =
        Memory.create_node(%{kind: :decision, body: "Sunset the legacy importer."})

      {:ok, _} = Memory.forget_node(decision)

      bodies = BulletinSynthesizer.bulletin_input_nodes() |> Enum.map(& &1.body)

      refute "Sunset the legacy importer." in bodies
    end
  end
end
