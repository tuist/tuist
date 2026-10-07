defmodule Atlas.SupportInbox.Agents.ClassifierAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Agents.Sessions
  alias Atlas.LLMs.Runner
  alias Atlas.SupportInbox.Agents.ClassifierAgent

  setup :verify_on_exit!

  describe "classify/1" do
    test "returns a normalized decision with atom category/urgency" do
      expect(Runner, :fetch_config, fn -> {:ok, %{mode: :test, model: "test-model"}} end)
      expect(Runner, :client_opts, fn _llm -> [] end)

      expect(Sessions, :run, fn ClassifierAgent, _prompt, opts ->
        assert Keyword.get(opts, :output)
        assert Keyword.get(opts, :load_project_instructions) == false

        {:ok,
         %{
           "category" => "invoice",
           "action_needed" => false,
           "urgency" => "none",
           "confidence" => 0.92,
           "reason" => "Cloudflare invoice, no action."
         }}
      end)

      assert {:ok, decision} =
               ClassifierAgent.classify(%{
                 from: "noreply@notify.cloudflare.com",
                 subject: "Your invoice is available",
                 body: nil,
                 has_attachments: true
               })

      assert decision.category == :invoice
      assert decision.action_needed == false
      assert decision.urgency == :none
      assert decision.confidence == 0.92
      assert decision.reason == "Cloudflare invoice, no action."
    end

    test "normalizes Condukt's atom-keyed structured result" do
      expect(Runner, :fetch_config, fn -> {:ok, %{mode: :test, model: "test-model"}} end)
      expect(Runner, :client_opts, fn _llm -> [] end)

      expect(Sessions, :run, fn ClassifierAgent, _prompt, opts ->
        assert Enum.all?(Keyword.fetch!(opts, :output).properties, fn {key, _} -> is_atom(key) end)

        {:ok,
         %{
           category: "publish",
           action_needed: false,
           urgency: "none",
           confidence: 0.92,
           reason: "Gradle plugin publication confirmation."
         }}
      end)

      assert {:ok, decision} =
               ClassifierAgent.classify(%{
                 from: "no-reply@gradle.com",
                 subject: "[Gradle] Plugin dev.tuist published"
               })

      assert decision.category == :publish
      assert decision.action_needed == false
      assert decision.urgency == :none
      assert decision.confidence == 0.92
    end

    test "normalizes every category and urgency advertised in the output schema" do
      categories = [:support, :invoice, :vendor_notice, :shipping, :publish, :registration, :ar, :spam, :other]
      urgencies = [:none, :low, :normal, :high]

      stub(Runner, :fetch_config, fn -> {:ok, %{mode: :test, model: "test-model"}} end)
      stub(Runner, :client_opts, fn _llm -> [] end)

      for category <- categories, urgency <- urgencies do
        expect(Sessions, :run, fn ClassifierAgent, _prompt, opts ->
          schema = Keyword.fetch!(opts, :output)
          assert Atom.to_string(category) in schema.properties.category.enum
          assert Atom.to_string(urgency) in schema.properties.urgency.enum

          {:ok,
           %{
             category: Atom.to_string(category),
             action_needed: false,
             urgency: Atom.to_string(urgency),
             confidence: 0.92,
             reason: "Classification result."
           }}
        end)

        assert {:ok, decision} = ClassifierAgent.classify(%{from: "noreply@example.com", subject: "Notification"})
        assert decision.category == category
        assert decision.urgency == urgency
      end
    end

    test "rejects an unknown category with an error tuple" do
      expect(Runner, :fetch_config, fn -> {:ok, %{mode: :test, model: "test-model"}} end)
      expect(Runner, :client_opts, fn _llm -> [] end)

      expect(Sessions, :run, fn ClassifierAgent, _prompt, _opts ->
        {:ok,
         %{
           "category" => "not_a_real_category",
           "action_needed" => true,
           "urgency" => "normal",
           "confidence" => 0.5,
           "reason" => "..."
         }}
      end)

      assert {:error, {:invalid_enum, "category", "not_a_real_category"}} =
               ClassifierAgent.classify(%{from: "x@example.com", subject: "hi"})
    end

    test "propagates :llm_not_configured" do
      expect(Runner, :fetch_config, fn -> {:error, :llm_not_configured} end)

      assert {:error, :llm_not_configured} =
               ClassifierAgent.classify(%{from: "x@example.com", subject: "hi"})
    end
  end
end
