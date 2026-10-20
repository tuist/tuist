defmodule Tuist.Accounts.Workers.DeliverConfirmationInstructionsWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Accounts.Workers.DeliverConfirmationInstructionsWorker
  alias Tuist.Repo

  describe "perform/1" do
    test "delivers the confirmation email" do
      user = %User{id: 1, email: "user@example.com"}
      confirmation_url = "https://tuist.dev/users/confirm/token"

      expect(Repo, :get, fn User, 1 -> user end)

      expect(UserNotifier, :deliver_confirmation_instructions, fn delivery ->
        assert delivery.user.id == user.id
        assert delivery.confirmation_url == confirmation_url
        {:ok, :stub_email}
      end)

      job = DeliverConfirmationInstructionsWorker.new_confirmation_instructions(user.id, confirmation_url)

      assert :ok = DeliverConfirmationInstructionsWorker.perform(oban_job(job))
    end

    test "retries when email delivery fails" do
      user = %User{id: 1, email: "user@example.com"}

      expect(Repo, :get, fn User, 1 -> user end)

      expect(UserNotifier, :deliver_confirmation_instructions, fn _ ->
        {:error, :mailgun_internal_server_error}
      end)

      job =
        DeliverConfirmationInstructionsWorker.new_confirmation_instructions(
          user.id,
          "https://tuist.dev/users/confirm/token"
        )

      assert {:error, :mailgun_internal_server_error} =
               DeliverConfirmationInstructionsWorker.perform(oban_job(job))
    end

    test "does not persist the confirmation URL in plaintext" do
      confirmation_url = "https://tuist.dev/users/confirm/token"

      job =
        DeliverConfirmationInstructionsWorker.new_confirmation_instructions(1, confirmation_url)

      args = oban_job(job).args

      refute Map.has_key?(args, "confirmation_url")
      refute args["encrypted_confirmation_url"] == confirmation_url
    end

    test "does not retry when the user has been deleted" do
      expect(Repo, :get, fn User, -1 -> nil end)

      job =
        DeliverConfirmationInstructionsWorker.new_confirmation_instructions(
          -1,
          "https://tuist.dev/users/confirm/token"
        )

      assert :ok = DeliverConfirmationInstructionsWorker.perform(oban_job(job))
    end
  end

  defp oban_job(changeset) do
    args = Map.new(changeset.changes.args, fn {key, value} -> {to_string(key), value} end)
    %Oban.Job{args: args}
  end
end
