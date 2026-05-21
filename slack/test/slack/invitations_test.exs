defmodule Slack.InvitationsTest do
  use Slack.DataCase, async: true

  import Swoosh.TestAssertions

  alias Slack.Invitations
  alias Slack.Invitations.Invitation

  @valid_reason "We use Tuist to speed up our CI builds and want to chat with other users."

  defp build_confirm_url, do: fn token -> "https://slack.tuist.dev/invitations/confirm/#{token}" end

  defp valid_attrs(overrides) do
    Map.merge(
      %{
        "email" => "user@tuist.dev",
        "reason" => @valid_reason,
        "code_of_conduct_accepted" => "true"
      },
      overrides
    )
  end

  describe "request_invitation/2" do
    test "stores a pending invitation and sends a confirmation email" do
      attrs = valid_attrs(%{"email" => "  Pedro@Tuist.dev "})

      assert {:ok, %Invitation{} = invitation} =
               Invitations.request_invitation(attrs, build_confirm_url())

      assert invitation.email == "pedro@tuist.dev"
      assert invitation.reason == @valid_reason
      assert invitation.code_of_conduct_accepted == true
      assert invitation.status == :unconfirmed
      assert is_binary(invitation.confirmation_token)
      assert byte_size(invitation.confirmation_token) > 16

      assert_email_sent(fn email ->
        assert email.to == [{"", "pedro@tuist.dev"}]
        assert email.subject =~ "Confirm"
        assert email.text_body =~ invitation.confirmation_token
      end)
    end

    test "requires a syntactically valid email" do
      assert {:error, changeset} =
               Invitations.request_invitation(
                 valid_attrs(%{"email" => "not-an-email"}),
                 build_confirm_url()
               )

      assert "must be a valid email address" in errors_on(changeset).email
      assert_no_email_sent()
    end

    test "requires a reason of at least 10 characters" do
      assert {:error, changeset} =
               Invitations.request_invitation(
                 valid_attrs(%{"reason" => "too short"}),
                 build_confirm_url()
               )

      assert Enum.any?(errors_on(changeset).reason, &String.contains?(&1, "should be at least"))
      assert_no_email_sent()
    end

    test "requires the reason to be present" do
      assert {:error, changeset} =
               Invitations.request_invitation(
                 valid_attrs(%{"reason" => ""}),
                 build_confirm_url()
               )

      assert "can't be blank" in errors_on(changeset).reason
    end

    test "requires the code of conduct to be accepted" do
      assert {:error, changeset} =
               Invitations.request_invitation(
                 valid_attrs(%{"code_of_conduct_accepted" => "false"}),
                 build_confirm_url()
               )

      assert "must be accepted to continue" in errors_on(changeset).code_of_conduct_accepted
      assert_no_email_sent()
    end

    test "rejects duplicate emails case-insensitively" do
      assert {:ok, _} =
               Invitations.request_invitation(
                 valid_attrs(%{"email" => "duplicate@tuist.dev"}),
                 build_confirm_url()
               )

      assert {:error, changeset} =
               Invitations.request_invitation(
                 valid_attrs(%{"email" => "DUPLICATE@tuist.dev"}),
                 build_confirm_url()
               )

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "confirm_invitation/1" do
    test "marks an unconfirmed invitation as pending" do
      {:ok, invitation} =
        Invitations.request_invitation(
          valid_attrs(%{"email" => "confirm@tuist.dev"}),
          build_confirm_url()
        )

      assert {:ok, confirmed} = Invitations.confirm_invitation(invitation)
      assert confirmed.status == :pending
      assert %DateTime{} = confirmed.confirmed_at
    end

    test "is idempotent for already-confirmed invitations" do
      {:ok, invitation} =
        Invitations.request_invitation(
          valid_attrs(%{"email" => "again@tuist.dev"}),
          build_confirm_url()
        )

      {:ok, confirmed} = Invitations.confirm_invitation(invitation)
      assert {:ok, ^confirmed} = Invitations.confirm_invitation(confirmed)
    end
  end

  describe "list_invitations/1" do
    setup do
      {:ok, unconfirmed} =
        Invitations.request_invitation(
          valid_attrs(%{"email" => "unconfirmed@tuist.dev"}),
          build_confirm_url()
        )

      {:ok, pending_invitation} =
        Invitations.request_invitation(
          valid_attrs(%{"email" => "pending@tuist.dev"}),
          build_confirm_url()
        )

      {:ok, pending} = Invitations.confirm_invitation(pending_invitation)

      {:ok, accepted_invitation} =
        Invitations.request_invitation(
          valid_attrs(%{"email" => "accepted@tuist.dev"}),
          build_confirm_url()
        )

      {:ok, confirmed_accepted} = Invitations.confirm_invitation(accepted_invitation)
      {:ok, accepted} = Invitations.accept_invitation(confirmed_accepted)

      %{unconfirmed: unconfirmed, pending: pending, accepted: accepted}
    end

    test "hides unconfirmed invitations by default", ctx do
      emails = ctx |> Map.take([:pending, :accepted]) |> Map.values() |> Enum.map(& &1.email)
      listed = Enum.map(Invitations.list_invitations(), & &1.email)
      assert Enum.sort(listed) == Enum.sort(emails)
    end

    test "can filter to unconfirmed invitations", ctx do
      assert [listed] = Invitations.list_invitations(statuses: [:unconfirmed])
      assert listed.email == ctx.unconfirmed.email
    end
  end

  describe "accept_invitation/1" do
    test "marks a pending invitation as accepted" do
      {:ok, invitation} =
        Invitations.request_invitation(
          valid_attrs(%{"email" => "accept@tuist.dev"}),
          build_confirm_url()
        )

      {:ok, pending} = Invitations.confirm_invitation(invitation)

      assert {:ok, accepted} = Invitations.accept_invitation(pending)
      assert accepted.status == :accepted
      assert %DateTime{} = accepted.accepted_at
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
