defmodule Atlas.Memory.Workers.RefreshBulletinTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Memory
  alias Atlas.Memory.BulletinSynthesizer
  alias Atlas.Memory.Workers.RefreshBulletin

  setup :verify_on_exit!

  test "upserts the synthesized bulletin into the global scope" do
    expect(BulletinSynthesizer, :synthesize_global, fn ->
      {:ok, "Acme renews in Q3."}
    end)

    assert :ok = perform_job(RefreshBulletin, %{"scope" => "global"})

    assert %{body: "Acme renews in Q3.", scope: :global} = Memory.get_bulletin(:global)
  end

  test "leaves the previous bulletin untouched when synthesis returns empty" do
    {:ok, _} = Memory.upsert_bulletin(:global, "Earlier bulletin.")

    expect(BulletinSynthesizer, :synthesize_global, fn -> {:ok, :empty} end)

    assert :ok = perform_job(RefreshBulletin, %{"scope" => "global"})

    assert %{body: "Earlier bulletin."} = Memory.get_bulletin(:global)
  end

  test "cancels permanently when the LLM is not configured" do
    expect(BulletinSynthesizer, :synthesize_global, fn -> {:error, :llm_not_configured} end)

    assert {:cancel, :llm_not_configured} = perform_job(RefreshBulletin, %{"scope" => "global"})
  end

  defp perform_job(worker, args) do
    worker.perform(%Oban.Job{args: args})
  end
end
