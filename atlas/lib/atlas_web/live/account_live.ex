defmodule AtlasWeb.AccountLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.AccountLive.Formatters
  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.RevenueComponents
  import Noora.Time

  alias Atlas.Accounts
  alias Atlas.Accounts.Account.Address
  alias Atlas.Accounts.Account.Billing
  alias Atlas.Accounts.Account.Signatory
  alias Atlas.Accounts.Agents.ScreenshotNoteAgent
  alias Atlas.Accounts.Amounts
  alias Atlas.Accounts.DealStage
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposal
  alias Atlas.Accounts.POCs
  alias Atlas.Audit
  alias Atlas.Letters
  alias Atlas.LLMs
  alias Atlas.Nudges
  alias Atlas.Slack
  alias Atlas.Users
  alias AtlasWeb.AccountLive.FeatureUsageView
  alias AtlasWeb.AccountLive.InvoicesView
  alias AtlasWeb.AccountLive.Screenshots
  alias AtlasWeb.DocumentLinks
  alias AtlasWeb.Utilities.Query

  require Logger

  # Hold the processing indicator on screen for at least this long even when
  # the LLM responds faster, so the spinner never flashes by invisibly.
  @screenshot_min_processing_ms 600
  def mount(%{"id" => id}, _session, socket) do
    case Accounts.get_account(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Account not found."))
         |> push_navigate(to: ~p"/commercial/sales/accounts")}

      account ->
        {:ok,
         socket
         |> assign(:page_title, account.name)
         |> assign(:feature_usage_view, FeatureUsageView.build(account))
         |> assign(:invoices_view, InvoicesView.build(account, 1))
         |> assign(:invoices_page, 1)
         |> assign(:screenshot_processing, false)
         |> assign(:screenshot_error, nil)
         |> assign(:staged_screenshots, [])
         |> assign(:overview_summary_processing, false)
         |> assign(:overview_summary_error, nil)
         |> assign(:dismiss_nudge_id, nil)
         |> assign(:dismiss_nudge_form, to_form(%{"reason" => ""}, as: "dismiss_nudge"))
         |> assign(:outcome_proposals_processing, false)
         |> assign(:outcome_proposals_error, nil)
         |> assign_favicon(account)
         |> assign_account(account)
         |> allow_upload(:signed_tax_certificate_request,
           accept: ~w(.pdf),
           max_entries: 1,
           max_file_size: 50_000_000
         )}
    end
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)
    uri = URI.new!("?" <> URI.encode_query(params))
    page = Query.parse_page(params["invoices-page"])

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign(:invoices_page, page)
     |> assign(:invoices_view, InvoicesView.build(socket.assigns.account, page))}
  end

  defp assign_favicon(socket, %{primary_domain: domain}) when is_binary(domain) and domain != "" do
    href = domain_favicon_url(domain)

    socket
    |> assign(:favicon_href, href)
    |> push_event("set-favicon", %{href: href})
  end

  defp assign_favicon(socket, _account), do: socket

  def handle_event("refresh_overview_summary", _params, socket) do
    cond do
      socket.assigns.overview_summary_processing ->
        {:noreply, socket}

      is_nil(LLMs.config()) ->
        {:noreply,
         assign(
           socket,
           :overview_summary_error,
           gettext("Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server.")
         )}

      true ->
        account_id = socket.assigns.account.id
        audit_context = Audit.current_context()

        {:noreply,
         socket
         |> assign(:overview_summary_processing, true)
         |> assign(:overview_summary_error, nil)
         |> start_async(:overview_summary_refresh, fn ->
           Audit.with_context(audit_context, fn ->
             Accounts.refresh_overview_summary(account_id)
           end)
         end)}
    end
  end

  def handle_event("save_account", %{"account" => params}, socket) do
    {slack_value, account_params} = Map.pop(params, "slack_channel")
    slack_value = normalize_slack_channel_value(slack_value)

    case Accounts.update_account(socket.assigns.account, account_params) do
      {:ok, account} ->
        Slack.set_account_channel(account, slack_value, socket.assigns.slack_channel_options)
        account = Accounts.get_account(account.id)

        {:noreply,
         socket
         |> assign(:page_title, account.name)
         |> assign_account(account)
         |> push_event("close-modal", %{id: "edit-account-modal"})
         |> push_event("close-modal", %{id: "edit-billing-modal"})}

      {:error, changeset} ->
        {:noreply, assign(socket, :account_form, to_form(changeset, as: "account"))}
    end
  end

  def handle_event("send_tax_certificate_request", %{"tax_certificate" => params}, socket) do
    case Letters.prepare_tax_certificate(socket.assigns.account, params, socket.assigns.current_user) do
      {:ok, _letter} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> put_flash(:info, gettext("The ready-to-sign request is available on this account."))
         |> push_event("close-modal", %{id: "tax-certificate-request-modal"})}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:tax_certificate_form, to_form(changeset, as: "tax_certificate"))
         |> push_event("open-modal", %{id: "tax-certificate-request-modal"})}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, gettext("Only leadership can prepare letters."))}

      {:error, {:sender_details_missing, fields}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Complete the Tuist GmbH tax-certificate profile before sending: %{fields}.",
             fields: Enum.join(fields, ", ")
           )
         )
         |> push_event("open-modal", %{id: "tax-certificate-request-modal"})}
    end
  end

  def handle_event("close_tax_certificate_request_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_tax_certificate_request_form(socket.assigns.account)
     |> push_event("close-modal", %{id: "tax-certificate-request-modal"})}
  end

  def handle_event("validate_signed_tax_certificate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("close_signed_tax_certificate_upload_modal", %{"id" => letter_id}, socket) do
    {:noreply, push_event(socket, "close-modal", %{id: signed_tax_certificate_upload_modal_id(letter_id)})}
  end

  def handle_event("close_signed_tax_certificate_upload_modal", _params, socket), do: {:noreply, socket}

  def handle_event("upload_signed_tax_certificate_request", %{"letter_id" => letter_id}, socket) do
    results =
      consume_uploaded_entries(socket, :signed_tax_certificate_request, fn %{path: path}, entry ->
        with {:ok, body} <- File.read(path),
             {:ok, letter} <-
               Letters.attach_letter_document(
                 letter_id,
                 %{body: body, filename: entry.client_name},
                 socket.assigns.current_user
               ) do
          {:ok, {:ok, letter}}
        else
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [{:ok, _letter}] ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> put_flash(:info, gettext("Signed request uploaded. Delivery details are being prepared."))
         |> push_event("close-modal", %{id: signed_tax_certificate_upload_modal_id(letter_id)})}

      [{:error, :letter_document_must_be_a_pdf}] ->
        {:noreply, put_flash(socket, :error, gettext("Upload a signed PDF document."))}

      [{:error, :letter_not_waiting_for_document}] ->
        {:noreply, put_flash(socket, :error, gettext("This request is no longer waiting for a signature."))}

      [{:error, _reason}] ->
        {:noreply, put_flash(socket, :error, gettext("Could not upload the signed request."))}

      [] ->
        {:noreply, put_flash(socket, :error, gettext("Choose the signed PDF before uploading it."))}
    end
  end

  def handle_event("select_account_slack_channel", %{"value" => value}, socket) do
    {:noreply, assign_selected_slack_channel(socket, value)}
  end

  def handle_event("open_new_contact_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_contact_modal(:create, nil)
     |> push_event("open-modal", %{id: "contact-modal"})}
  end

  def handle_event("open_edit_contact_modal", %{"id" => id}, socket) do
    case find_contact(socket.assigns.account, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Contact not found."))}

      contact ->
        {:noreply,
         socket
         |> assign_contact_modal(:edit, contact)
         |> push_event("open-modal", %{id: "contact-modal"})}
    end
  end

  def handle_event("delete_contact", _params, socket) do
    case socket.assigns.selected_contact do
      nil ->
        {:noreply, socket}

      contact ->
        case Accounts.delete_contact(contact) do
          {:ok, _contact} ->
            account = Accounts.get_account(socket.assigns.account.id)

            {:noreply,
             socket
             |> assign_account(account)
             |> assign_contact_modal(:create, nil)
             |> push_event("close-modal", %{id: "contact-modal"})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to remove contact."))}
        end
    end
  end

  def handle_event("delete_account", _params, socket) do
    case Accounts.delete_account(socket.assigns.account) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Account deleted."))
         |> push_navigate(to: ~p"/commercial/sales/accounts")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to delete account."))}
    end
  end

  def handle_event("mark_not_account", _params, socket) do
    case Accounts.mark_account_not_account(socket.assigns.account, %{
           reason: "Marked manually from the account page"
         }) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Account marked as not an account."))
         |> push_navigate(to: ~p"/commercial/sales/accounts")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to mark account as not an account."))}
    end
  end

  def handle_event("save_contact", %{"contact" => params}, socket) do
    result =
      case socket.assigns.selected_contact do
        nil -> Accounts.create_contact(socket.assigns.account, params)
        contact -> Accounts.update_contact(contact, params)
      end

    case result do
      {:ok, _contact} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> assign_contact_modal(:create, nil)
         |> push_event("close-modal", %{id: "contact-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:contact_form, to_form(changeset, as: "contact"))
         |> push_event("open-modal", %{id: "contact-modal"})}
    end
  end

  def handle_event("add_handle", %{"account_handle" => params}, socket) do
    case Accounts.create_account_handle(socket.assigns.account, params) do
      {:ok, _account_handle} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> push_event("open-modal", %{id: "edit-account-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:handle_form, to_form(changeset, as: "account_handle"))
         |> push_event("open-modal", %{id: "edit-account-modal"})}
    end
  end

  def handle_event("remove_handle", params, socket) do
    id = params["id"] || params["data"]

    case Accounts.delete_account_handle(socket.assigns.account, id) do
      {:ok, _account_handle} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> push_event("open-modal", %{id: "edit-account-modal"})}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Handle not found."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to remove handle."))}
    end
  end

  def handle_event("open_new_outcome_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_outcome_modal()
     |> push_event("open-modal", %{id: "outcome-modal"})}
  end

  def handle_event("close_outcome_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_outcome_modal()
     |> push_event("close-modal", %{id: "outcome-modal"})}
  end

  def handle_event("save_outcome", %{"outcome" => params}, socket) do
    case Accounts.create_outcome(socket.assigns.account, params, socket.assigns.current_user) do
      {:ok, _outcome} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> assign_outcome_modal()
         |> push_event("close-modal", %{id: "outcome-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:outcome_form, to_form(changeset, as: "outcome"))
         |> push_event("open-modal", %{id: "outcome-modal"})}
    end
  end

  def handle_event("open_outcome_review_modal", %{"id" => id}, socket) do
    case find_outcome(socket.assigns.account, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Outcome not found."))}

      outcome ->
        {:noreply,
         socket
         |> assign_outcome_review_modal(outcome)
         |> push_event("open-modal", %{id: "outcome-review-modal"})}
    end
  end

  def handle_event("close_outcome_review_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_outcome, nil)
     |> assign(:outcome_review_form, nil)
     |> push_event("close-modal", %{id: "outcome-review-modal"})}
  end

  def handle_event("save_outcome_review", %{"outcome_review" => params}, socket) do
    case Accounts.create_outcome_review(socket.assigns.selected_outcome, params, socket.assigns.current_user) do
      {:ok, _review} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> push_event("close-modal", %{id: "outcome-review-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:outcome_review_form, to_form(changeset, as: "outcome_review"))
         |> push_event("open-modal", %{id: "outcome-review-modal"})}
    end
  end

  def handle_event("achieve_outcome", %{"id" => id}, socket) do
    with %Outcome{} = outcome <- find_outcome(socket.assigns.account, id),
         {:ok, _outcome} <- Accounts.update_outcome(outcome, %{status: "achieved", health: "on_track"}) do
      {:noreply, assign_account(socket, Accounts.get_account(socket.assigns.account.id))}
    else
      _result -> {:noreply, put_flash(socket, :error, gettext("Failed to mark outcome as achieved."))}
    end
  end

  def handle_event("generate_outcome_proposals", _params, socket) do
    cond do
      socket.assigns.outcome_proposals_processing ->
        {:noreply, socket}

      is_nil(LLMs.config()) ->
        {:noreply,
         assign(
           socket,
           :outcome_proposals_error,
           gettext("Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server.")
         )}

      true ->
        account_id = socket.assigns.account.id
        audit_context = Audit.current_context()

        {:noreply,
         socket
         |> assign(:outcome_proposals_processing, true)
         |> assign(:outcome_proposals_error, nil)
         |> start_async(:outcome_proposals_generation, fn ->
           Audit.with_context(audit_context, fn ->
             Accounts.generate_outcome_proposals(account_id)
           end)
         end)}
    end
  end

  def handle_event("claim_nudge", %{"id" => id}, socket) do
    case Nudges.claim(id, socket.assigns.current_user) do
      {:ok, _nudge} ->
        {:noreply, refresh_nudges(socket, gettext("You now own this nudge."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Nudge not found."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not claim the nudge."))}
    end
  end

  def handle_event("send_nudge", %{"id" => id}, socket) do
    handle_send_result(Nudges.send(id, socket.assigns.current_user), socket)
  end

  def handle_event("retry_nudge", %{"id" => id}, socket) do
    case Nudges.retry(id) do
      {:ok, _nudge} ->
        {:noreply, refresh_nudges(socket, gettext("Ready to send again."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Nudge not found."))}

      {:error, {:retry_not_allowed, stage}} ->
        {:noreply, put_flash(socket, :error, gettext("Retry not allowed while delivery is %{s}.", s: to_string(stage)))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not retry the nudge."))}
    end
  end

  def handle_event("release_nudge", %{"id" => id}, socket) do
    case Nudges.release(id) do
      {:ok, _nudge} ->
        {:noreply, refresh_nudges(socket, gettext("Nudge released."))}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Nudge not found."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not release the nudge."))}
    end
  end

  def handle_event("open_dismiss_nudge_modal", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:dismiss_nudge_id, id)
     |> assign(:dismiss_nudge_form, to_form(%{"reason" => ""}, as: "dismiss_nudge"))
     |> push_event("open-modal", %{id: "dismiss-nudge-modal"})}
  end

  def handle_event("close_dismiss_nudge_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:dismiss_nudge_id, nil)
     |> assign(:dismiss_nudge_form, to_form(%{"reason" => ""}, as: "dismiss_nudge"))
     |> push_event("close-modal", %{id: "dismiss-nudge-modal"})}
  end

  def handle_event("dismiss_nudge", %{"dismiss_nudge" => %{"reason" => reason}}, socket) do
    nudge_id = socket.assigns.dismiss_nudge_id
    trimmed = String.trim(reason || "")

    cond do
      is_nil(nudge_id) ->
        {:noreply, put_flash(socket, :error, gettext("No nudge selected."))}

      trimmed == "" ->
        {:noreply,
         assign(
           socket,
           :dismiss_nudge_form,
           to_form(%{"reason" => reason}, as: "dismiss_nudge", errors: [reason: {"can't be blank", []}])
         )}

      true ->
        case Nudges.dismiss(nudge_id, %{dismissed_reason: trimmed}) do
          {:ok, _nudge} ->
            {:noreply,
             socket
             |> assign(:dismiss_nudge_id, nil)
             |> assign(:dismiss_nudge_form, to_form(%{"reason" => ""}, as: "dismiss_nudge"))
             |> push_event("close-modal", %{id: "dismiss-nudge-modal"})
             |> refresh_nudges(gettext("Nudge dismissed."))}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, gettext("Nudge not found."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, gettext("Could not dismiss the nudge."))}
        end
    end
  end

  def handle_event("open_outcome_proposal_modal", %{"id" => id}, socket) do
    case Accounts.get_outcome_proposal(socket.assigns.account, id) do
      %OutcomeProposal{status: "pending"} = proposal ->
        {:noreply,
         socket
         |> assign_outcome_proposal_modal(proposal)
         |> push_event("open-modal", %{id: "outcome-proposal-modal"})}

      _proposal ->
        {:noreply, put_flash(socket, :error, gettext("Outcome suggestion not found."))}
    end
  end

  def handle_event("close_outcome_proposal_modal", _params, socket) do
    {:noreply,
     socket
     |> clear_outcome_proposal_modal()
     |> push_event("close-modal", %{id: "outcome-proposal-modal"})}
  end

  def handle_event("approve_outcome_proposal", %{"outcome_proposal" => params}, socket) do
    proposal = socket.assigns.selected_outcome_proposal
    actor = socket.assigns.current_user

    with %OutcomeProposal{} <- proposal,
         {:ok, updated} <- Accounts.update_outcome_proposal(proposal, params, actor),
         {:ok, _result} <- Accounts.approve_outcome_proposal(updated, actor) do
      account = Accounts.get_account(socket.assigns.account.id)

      {:noreply,
       socket
       |> assign_account(account)
       |> put_flash(:info, gettext("Outcome suggestion approved."))
       |> push_event("close-modal", %{id: "outcome-proposal-modal"})}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:outcome_proposal_form, to_form(changeset, as: "outcome_proposal"))
         |> push_event("open-modal", %{id: "outcome-proposal-modal"})}

      _result ->
        {:noreply, put_flash(socket, :error, gettext("Could not approve outcome suggestion."))}
    end
  end

  def handle_event("reject_outcome_proposal", %{"proposal_decision" => %{"reason" => reason}}, socket) do
    proposal = socket.assigns.selected_outcome_proposal

    case proposal && Accounts.reject_outcome_proposal(proposal, reason, socket.assigns.current_user) do
      {:ok, _proposal} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> put_flash(:info, gettext("Outcome suggestion rejected."))
         |> push_event("close-modal", %{id: "outcome-proposal-modal"})}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Add a reason before rejecting the suggestion."))
         |> push_event("open-modal", %{id: "outcome-proposal-modal"})}

      _result ->
        {:noreply, put_flash(socket, :error, gettext("Could not reject outcome suggestion."))}
    end
  end

  def handle_event("add_note", %{"note" => params}, socket) do
    case Accounts.create_note(socket.assigns.account, params, socket.assigns.current_user) do
      {:ok, _event} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> assign(:staged_screenshots, [])
         |> push_event("set-note-body", %{body: ""})}

      {:error, changeset} ->
        {:noreply, assign(socket, :note_form, to_form(changeset, as: "note"))}
    end
  end

  def handle_event("open_feature_interest_modal", _params, socket) do
    if socket.assigns.account.events == [] do
      {:noreply, put_flash(socket, :error, gettext("Add a timeline event before recording feature interest."))}
    else
      {:noreply,
       socket
       |> assign_feature_interest_modal()
       |> push_event("open-modal", %{id: "feature-interest-modal"})}
    end
  end

  def handle_event("close_feature_interest_modal", _params, socket) do
    {:noreply,
     socket
     |> clear_feature_interest_modal()
     |> push_event("close-modal", %{id: "feature-interest-modal"})}
  end

  def handle_event("record_feature_interest", %{"feature_interest" => params}, socket) do
    case Accounts.get_account_event(socket.assigns.account, params["account_event_id"]) do
      {:ok, event} ->
        result =
          Audit.with_context(%{actor: socket.assigns.current_user, interface: "dashboard"}, fn ->
            Accounts.record_feature_interest_from_event(event, params, socket.assigns.current_user)
          end)

        case result do
          {:ok, %{interest: interest}} ->
            account = Accounts.get_account(socket.assigns.account.id)

            {:noreply,
             socket
             |> assign_account(account)
             |> put_flash(:info, gettext("Feature interest recorded for %{feature}.", feature: interest.title))
             |> push_event("close-modal", %{id: "feature-interest-modal"})}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:feature_interest_form, to_form(changeset, as: "feature_interest"))
             |> push_event("open-modal", %{id: "feature-interest-modal"})}
        end

      {:error, :event_not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("Choose a timeline event before recording feature interest."))
         |> push_event("open-modal", %{id: "feature-interest-modal"})}
    end
  end

  def handle_event("open_feature_interest_notes_modal", %{"id" => id}, socket) do
    case find_feature_interest_account(socket.assigns.feature_interests, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Feature interest record not found."))}

      interest_account ->
        {:noreply,
         socket
         |> assign_feature_interest_notes_modal(interest_account)
         |> push_event("open-modal", %{id: "feature-interest-notes-modal"})}
    end
  end

  def handle_event("close_feature_interest_notes_modal", _params, socket) do
    {:noreply,
     socket
     |> clear_feature_interest_notes_modal()
     |> push_event("close-modal", %{id: "feature-interest-notes-modal"})}
  end

  def handle_event("save_feature_interest_notes", %{"feature_interest_notes" => params}, socket) do
    case socket.assigns.selected_feature_interest_account do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Feature interest record not found."))}

      interest_account ->
        result =
          Audit.with_context(%{actor: socket.assigns.current_user, interface: "dashboard"}, fn ->
            Accounts.update_feature_interest_notes(interest_account, params, socket.assigns.current_user)
          end)

        case result do
          {:ok, _updated_interest_account} ->
            account = Accounts.get_account(socket.assigns.account.id)

            {:noreply,
             socket
             |> assign_account(account)
             |> push_event("close-modal", %{id: "feature-interest-notes-modal"})}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:feature_interest_notes_form, to_form(changeset, as: "feature_interest_notes"))
             |> push_event("open-modal", %{id: "feature-interest-notes-modal"})}
        end
    end
  end

  def handle_event("screenshot_pasted", params, socket) do
    handle_event("screenshots_pasted", %{"screenshots" => [params]}, socket)
  end

  def handle_event("screenshots_pasted", %{"screenshots" => screenshots}, socket) when is_list(screenshots) do
    if socket.assigns.screenshot_processing do
      {:noreply, socket}
    else
      {staged_screenshots, error} = Screenshots.stage(socket.assigns.staged_screenshots, screenshots)

      socket =
        socket
        |> assign(:staged_screenshots, staged_screenshots)
        |> assign(:screenshot_error, error)

      socket =
        if staged_screenshots != [] and is_nil(error) do
          start_screenshot_analysis(socket)
        else
          socket
        end

      {:noreply, socket}
    end
  end

  def handle_event("remove_staged_screenshot", %{"id" => id}, socket) do
    if socket.assigns.screenshot_processing do
      {:noreply, socket}
    else
      staged_screenshots =
        Enum.reject(socket.assigns.staged_screenshots, fn screenshot -> screenshot.id == id end)

      {:noreply, assign(socket, :staged_screenshots, staged_screenshots)}
    end
  end

  def handle_event("clear_staged_screenshots", _params, socket) do
    if socket.assigns.screenshot_processing do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:staged_screenshots, [])
       |> assign(:screenshot_error, nil)}
    end
  end

  def handle_event("draft_from_screenshots", _params, socket) do
    {:noreply, start_screenshot_analysis(socket)}
  end

  def handle_event("close_edit_billing_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_account(socket.assigns.account)
     |> push_event("close-modal", %{id: "edit-billing-modal"})}
  end

  def handle_event("open_new_term_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_term_modal(:create, nil)
     |> push_event("open-modal", %{id: "term-modal"})}
  end

  def handle_event("open_edit_term_modal", %{"id" => id}, socket) do
    case Accounts.get_term(socket.assigns.account, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Term not found."))}

      term ->
        {:noreply,
         socket
         |> assign_term_modal(:edit, term)
         |> push_event("open-modal", %{id: "term-modal"})}
    end
  end

  def handle_event("renew_term", %{"id" => id}, socket) do
    case Accounts.get_term(socket.assigns.account, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Term not found."))}

      term ->
        changeset = Accounts.renew_term_changeset(socket.assigns.account, term)

        {:noreply,
         socket
         |> assign(:term_modal_mode, :create)
         |> assign(:selected_term, nil)
         |> assign(:term_form, to_form(changeset, as: "term"))
         |> push_event("open-modal", %{id: "term-modal"})}
    end
  end

  def handle_event("close_term_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_term_modal(:create, nil)
     |> push_event("close-modal", %{id: "term-modal"})}
  end

  def handle_event("save_term", %{"term" => params}, socket) do
    result =
      case socket.assigns.selected_term do
        nil -> Accounts.create_term(socket.assigns.account, params)
        term -> Accounts.update_term(term, params)
      end

    case result do
      {:ok, _term} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> assign_term_modal(:create, nil)
         |> push_event("close-modal", %{id: "term-modal"})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:term_form, to_form(changeset, as: "term"))
         |> push_event("open-modal", %{id: "term-modal"})}
    end
  end

  def handle_event("delete_term", _params, socket) do
    case socket.assigns.selected_term do
      nil ->
        {:noreply, socket}

      term ->
        case Accounts.delete_term(term) do
          {:ok, _term} ->
            account = Accounts.get_account(socket.assigns.account.id)

            {:noreply,
             socket
             |> assign_account(account)
             |> assign_term_modal(:create, nil)
             |> push_event("close-modal", %{id: "term-modal"})}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to remove term."))}
        end
    end
  end

  def handle_event("close_edit_account_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_account(socket.assigns.account)
     |> push_event("close-modal", %{id: "edit-account-modal"})}
  end

  def handle_event("close_contact_modal", _params, socket) do
    {:noreply,
     socket
     |> assign_contact_modal(:create, nil)
     |> push_event("close-modal", %{id: "contact-modal"})}
  end

  def handle_async(:screenshot_analysis, {:ok, {:ok, draft}}, socket) when is_binary(draft) do
    body = String.trim(draft)

    case Accounts.create_note(socket.assigns.account, %{"body" => body}, socket.assigns.current_user) do
      {:ok, _event} ->
        account = Accounts.get_account(socket.assigns.account.id)

        {:noreply,
         socket
         |> assign_account(account)
         |> assign(:screenshot_processing, false)
         |> assign(:screenshot_error, nil)
         |> assign(:staged_screenshots, [])
         |> push_event("set-note-body", %{body: ""})}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:screenshot_processing, false)
         |> assign(
           :screenshot_error,
           gettext("Could not save the screenshot note. Review it and try again.")
         )
         |> assign(:note_form, to_form(changeset, as: "note"))
         |> push_event("set-note-body", %{body: body})}
    end
  end

  def handle_async(:screenshot_analysis, {:ok, {:error, :llm_not_configured}}, socket) do
    {:noreply,
     socket
     |> assign(:screenshot_processing, false)
     |> assign(
       :screenshot_error,
       gettext("Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server.")
     )}
  end

  def handle_async(:screenshot_analysis, {:ok, {:error, reason}}, socket) do
    Logger.error("Screenshot note drafting failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:screenshot_processing, false)
     |> assign(
       :screenshot_error,
       gettext("Could not analyze screenshot. Please try again.")
     )}
  end

  def handle_async(:screenshot_analysis, {:exit, reason}, socket) do
    Logger.error("Screenshot note drafting crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:screenshot_processing, false)
     |> assign(
       :screenshot_error,
       gettext("Could not analyze screenshot. Please try again.")
     )}
  end

  def handle_async(:overview_summary_refresh, {:ok, {:ok, account}}, socket) do
    account = Accounts.get_account(account.id)

    {:noreply,
     socket
     |> assign(:overview_summary_processing, false)
     |> assign(:overview_summary_error, nil)
     |> assign_account(account)}
  end

  def handle_async(:overview_summary_refresh, {:ok, {:error, :llm_not_configured}}, socket) do
    {:noreply,
     socket
     |> assign(:overview_summary_processing, false)
     |> assign(
       :overview_summary_error,
       gettext("Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server.")
     )}
  end

  def handle_async(:overview_summary_refresh, {:ok, {:error, reason}}, socket) do
    Logger.error("Overview summary refresh failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:overview_summary_processing, false)
     |> assign(:overview_summary_error, gettext("Could not summarize account. Please try again."))}
  end

  def handle_async(:overview_summary_refresh, {:exit, reason}, socket) do
    Logger.error("Overview summary refresh crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:overview_summary_processing, false)
     |> assign(:overview_summary_error, gettext("Could not summarize account. Please try again."))}
  end

  def handle_async(:outcome_proposals_generation, {:ok, {:ok, proposals}}, socket) do
    account = Accounts.get_account(socket.assigns.account.id)

    socket =
      socket
      |> assign(:outcome_proposals_processing, false)
      |> assign(:outcome_proposals_error, nil)
      |> assign_account(account)

    socket =
      if proposals == [] do
        put_flash(socket, :info, gettext("No new evidence-backed suggestions were found."))
      else
        put_flash(socket, :info, gettext("Outcome suggestions are ready for review."))
      end

    {:noreply, socket}
  end

  def handle_async(:outcome_proposals_generation, {:ok, {:error, :llm_not_configured}}, socket) do
    {:noreply,
     socket
     |> assign(:outcome_proposals_processing, false)
     |> assign(
       :outcome_proposals_error,
       gettext("Language model is not configured. Set LLM_API_KEY and LLM_MODEL on the server.")
     )}
  end

  def handle_async(:outcome_proposals_generation, {:ok, {:error, reason}}, socket) do
    Logger.error("Outcome suggestion generation failed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:outcome_proposals_processing, false)
     |> assign(:outcome_proposals_error, gettext("Could not generate outcome suggestions. Please try again."))}
  end

  def handle_async(:outcome_proposals_generation, {:exit, reason}, socket) do
    Logger.error("Outcome suggestion generation crashed: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:outcome_proposals_processing, false)
     |> assign(:outcome_proposals_error, gettext("Could not generate outcome suggestions. Please try again."))}
  end

  def render(assigns) do
    ~H"""
    <div id="account">
      <div data-part="action-buttons">
        <.button
          id="account-back-button"
          label={gettext("Accounts")}
          variant="secondary"
          size="medium"
          navigate={~p"/commercial/sales/accounts"}
        >
          <:icon_left>
            <.icon name="arrow_left" />
          </:icon_left>
        </.button>

        <div data-part="action-buttons-right">
          <.button
            :if={@account.primary_domain}
            id="account-website-link"
            label={gettext("Website")}
            variant="secondary"
            size="medium"
            href={website_url(@account.primary_domain)}
            target="_blank"
            rel="noopener noreferrer"
          >
            <:icon_right><.icon name="external_link" /></:icon_right>
          </.button>
          <.button
            :if={@account.stripe_customer_id}
            id="account-stripe-link"
            label={gettext("Stripe")}
            variant="secondary"
            size="medium"
            href={stripe_customer_url(@account.stripe_customer_id)}
            target="_blank"
            rel="noopener noreferrer"
          >
            <:icon_right><.icon name="external_link" /></:icon_right>
          </.button>
          <.modal
            :if={@leadership?}
            id="tax-certificate-request-modal"
            title={gettext("Generate tax certificate request")}
            description={
              gettext(
                "Tuist GmbH and its tax office are prefilled. The prepared request remains on this account until it is signed."
              )
            }
            header_type="icon"
            header_size="small"
            on_dismiss="close_tax_certificate_request_modal"
          >
            <:header_icon><.file /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                label={gettext("Generate tax certificate request")}
                size="medium"
                {modal_attrs}
              />
            </:trigger>

            <div data-part="tax-certificate-request-modal-content">
              <.form
                id="tax-certificate-request-form"
                for={@tax_certificate_form}
                phx-submit="send_tax_certificate_request"
              >
                <div data-part="account-settings-sections">
                  <div data-part="account-settings-section">
                    <div data-part="account-settings-section-header">
                      <span data-part="account-settings-section-title">{gettext("Recipient")}</span>
                      <span data-part="account-settings-section-subtitle">
                        {gettext(
                          "Tuist GmbH's responsible tax office is prefilled. Review it only if this request needs a different recipient."
                        )}
                      </span>
                    </div>

                    <div data-part="account-settings-grid">
                      <.text_input
                        id="tax-certificate-recipient-name-input"
                        field={@tax_certificate_form[:recipient_name]}
                        type="basic"
                        label={gettext("Tax office")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-recipient-reference-input"
                        field={@tax_certificate_form[:recipient_reference]}
                        type="basic"
                        label={gettext("Reference")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-recipient-street-input"
                        field={@tax_certificate_form[:recipient_street]}
                        type="basic"
                        label={gettext("Street")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-recipient-postal-code-input"
                        field={@tax_certificate_form[:recipient_postal_code]}
                        type="basic"
                        label={gettext("Postal code")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-recipient-city-input"
                        field={@tax_certificate_form[:recipient_city]}
                        type="basic"
                        label={gettext("City")}
                        show_suffix={false}
                      />
                    </div>
                  </div>

                  <div data-part="account-settings-section">
                    <div data-part="account-settings-section-header">
                      <span data-part="account-settings-section-title">
                        {gettext("Form details")}
                      </span>
                      <span data-part="account-settings-section-subtitle">
                        {gettext(
                          "Tuist GmbH's company details are prefilled. Enter the purpose for this request; the signature remains blank."
                        )}
                      </span>
                    </div>

                    <div data-part="account-settings-grid">
                      <.text_input
                        id="tax-certificate-foundation-date-input"
                        field={@tax_certificate_form[:foundation_date]}
                        type="basic"
                        input_type="date"
                        label={gettext("Incorporation date")}
                        required
                        show_required
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-legal-form-input"
                        field={@tax_certificate_form[:legal_form]}
                        type="basic"
                        label={gettext("Legal form")}
                        placeholder={gettext("GmbH")}
                        required
                        show_required
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-submission-to-input"
                        field={@tax_certificate_form[:submission_to]}
                        type="basic"
                        label={gettext("Submitted to")}
                        placeholder={gettext("Public contracting authority")}
                        required
                        show_required
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-purpose-input"
                        field={@tax_certificate_form[:certificate_purpose]}
                        type="basic"
                        label={gettext("Purpose")}
                        placeholder={gettext("Participation in a tender")}
                        required
                        show_required
                        show_suffix={false}
                      />
                      <.text_input
                        id="tax-certificate-signing-location-input"
                        field={@tax_certificate_form[:signing_location]}
                        type="basic"
                        label={gettext("Signing location")}
                        placeholder={gettext("Berlin")}
                        show_suffix={false}
                      />
                    </div>
                  </div>
                </div>
              </.form>
            </div>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="close_tax_certificate_request_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="send-tax-certificate-request-button"
                    label={gettext("Generate request")}
                    size="small"
                    type="submit"
                    form="tax-certificate-request-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
          <.dropdown
            id="account-actions-dropdown"
            icon_only
            size="medium"
            data-part="account-actions-dropdown"
          >
            <:icon><.dots_vertical /></:icon>

            <.dropdown_item
              id="mark-not-account-button"
              value="mark_not_account"
              label={gettext("Not an account")}
              on_click="mark_not_account"
              data-confirm={
                gettext(
                  "Mark this as not an account? Atlas will hide it from account lists and keep its identifiers to prevent agents from recreating it."
                )
              }
            >
              <:left_icon><.circle_x /></:left_icon>
            </.dropdown_item>
            <.dropdown_item
              id="delete-account-button"
              value="delete_account"
              label={gettext("Delete")}
              on_click="delete_account"
              data-confirm={
                gettext(
                  "Delete this account? Contacts, invoices, terms, and timeline events will also be removed. This cannot be undone."
                )
              }
            >
              <:left_icon><.trash /></:left_icon>
            </.dropdown_item>
          </.dropdown>
        </div>
      </div>

      <div data-part="header">
        <div data-part="title">
          <h1 data-part="label">{@account.name}</h1>
        </div>
        <p :if={@account.description} data-part="description">{@account.description}</p>
      </div>

      <.card
        :if={@leadership? and @ready_to_sign_tax_certificate_requests != []}
        title={gettext("Tax certificate requests")}
        icon="file"
        data-part="ready-to-sign-tax-certificate-requests-card"
      >
        <.card_section data-part="ready-to-sign-tax-certificate-requests-section">
          <div
            id="ready-to-sign-tax-certificate-requests"
            data-part="ready-to-sign-tax-certificate-requests"
          >
            <div
              :for={letter <- @ready_to_sign_tax_certificate_requests}
              id={"ready-to-sign-tax-certificate-request-#{letter.id}"}
              data-part="ready-to-sign-tax-certificate-request"
            >
              <div data-part="request-details">
                <span data-part="request-title">{letter.subject}</span>
                <span data-part="request-description">
                  {gettext("Download, sign, then upload the signed request here.")}
                </span>
              </div>
              <div data-part="request-actions">
                <.button
                  id={"download-ready-to-sign-tax-certificate-request-#{letter.id}"}
                  label={gettext("Download request")}
                  variant="secondary"
                  size="small"
                  href={DocumentLinks.download_path(letter.document)}
                  target="_blank"
                >
                  <:icon_left><.download /></:icon_left>
                </.button>
                <.modal
                  id={signed_tax_certificate_upload_modal_id(letter.id)}
                  title={gettext("Upload signed request")}
                  description={gettext("Attach the signed request to start delivery preparation.")}
                  header_type="icon"
                  header_size="small"
                  on_dismiss="close_signed_tax_certificate_upload_modal"
                >
                  <:header_icon><.file /></:header_icon>
                  <:trigger :let={modal_attrs}>
                    <.button
                      id={"upload-signed-tax-certificate-request-#{letter.id}"}
                      label={gettext("Upload signed request")}
                      size="small"
                      {modal_attrs}
                    >
                      <:icon_left><.file /></:icon_left>
                    </.button>
                  </:trigger>
                  <.form
                    id={"upload-signed-tax-certificate-request-form-#{letter.id}"}
                    for={@signed_tax_certificate_upload_form}
                    phx-change="validate_signed_tax_certificate_upload"
                    phx-submit="upload_signed_tax_certificate_request"
                    data-part="signed-tax-certificate-upload-form"
                  >
                    <input type="hidden" name="letter_id" value={letter.id} />
                    <label
                      id={"select-signed-tax-certificate-request-#{letter.id}"}
                      class="noora-button"
                      data-part="signed-tax-certificate-upload-button"
                      data-variant="secondary"
                      data-size="medium"
                    >
                      <.live_file_input
                        id={"signed-tax-certificate-request-file-input-#{letter.id}"}
                        upload={@uploads.signed_tax_certificate_request}
                        data-part="signed-tax-certificate-file-input"
                      />
                      <span>{gettext("Choose signed PDF")}</span>
                    </label>
                  </.form>
                  <:footer>
                    <.modal_footer>
                      <:action>
                        <.button
                          label={gettext("Cancel")}
                          variant="secondary"
                          size="small"
                          type="button"
                          phx-click="close_signed_tax_certificate_upload_modal"
                          phx-value-id={letter.id}
                        />
                      </:action>
                      <:action>
                        <.button
                          id={"submit-signed-tax-certificate-request-#{letter.id}"}
                          label={gettext("Upload signed request")}
                          size="small"
                          type="submit"
                          form={"upload-signed-tax-certificate-request-form-#{letter.id}"}
                        />
                      </:action>
                    </.modal_footer>
                  </:footer>
                </.modal>
              </div>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card
        title={gettext("Overview")}
        icon="building"
        data-part="overview-card"
        style={overview_card_style(@account)}
      >
        <:actions>
          <div data-part="overview-card-actions">
            <.button
              id="refresh-overview-summary-button"
              label={
                if @overview_summary_processing,
                  do: gettext("Summarizing…"),
                  else: gettext("Summarize")
              }
              variant="secondary"
              size="small"
              type="button"
              phx-click="refresh_overview_summary"
              disabled={@overview_summary_processing}
            />

            <.modal
              id="edit-account-modal"
              title={gettext("Edit Account")}
              description={
                gettext(
                  "Update account details, revenue fields, reconciliation identifiers, and handles."
                )
              }
              header_type="icon"
              header_size="small"
              on_dismiss="close_edit_account_modal"
            >
              <:header_icon><.atom /></:header_icon>
              <:trigger :let={modal_attrs}>
                <.button
                  id="edit-account-button"
                  label={gettext("Edit")}
                  variant="secondary"
                  size="small"
                  {modal_attrs}
                />
              </:trigger>

              <div data-part="account-settings-modal-content">
                <.form id="edit-account-form" for={@account_form} phx-submit="save_account">
                  <div data-part="account-settings-sections">
                    <div data-part="account-settings-section">
                      <div data-part="account-settings-section-header">
                        <span data-part="account-settings-section-title">{gettext("Identity")}</span>
                        <span data-part="account-settings-section-subtitle">
                          {gettext(
                            "How the account appears in Atlas and links out to external systems."
                          )}
                        </span>
                      </div>

                      <div data-part="account-settings-grid">
                        <.text_input
                          id="account-name-input"
                          field={@account_form[:name]}
                          type="basic"
                          label={gettext("Name")}
                          required
                          show_required
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-primary-domain-input"
                          field={@account_form[:primary_domain]}
                          type="basic"
                          label={gettext("Primary domain")}
                          placeholder={gettext("deliveryhero.com")}
                          show_suffix={false}
                        />
                        <div data-part="account-settings-select">
                          <.label label={gettext("Parent account")} />
                          <.select
                            id="account-parent-account-select"
                            name="account[parent_account_id]"
                            label={gettext("Select parent account")}
                            value={select_value(@account_form[:parent_account_id].value)}
                          >
                            <:item value="_none" label={gettext("None")} />
                            <:item
                              :for={option <- @parent_account_options}
                              value={option.id}
                              label={parent_account_option_label(option)}
                            />
                          </.select>
                        </div>
                        <div data-part="account-settings-grid-full">
                          <.text_area
                            id="account-description-input"
                            field={@account_form[:description]}
                            label={gettext("Description")}
                            placeholder={
                              gettext("Relationship context, commercial notes, or account summary")
                            }
                            rows={3}
                            max_length={600}
                          />
                        </div>
                        <div data-part="account-settings-grid-full">
                          <div data-part="account-settings-select">
                            <.label label={gettext("Slack channel")} />
                            <input
                              id="account-slack-channel-input"
                              type="hidden"
                              name="account[slack_channel]"
                              value={@selected_slack_channel_value}
                            />
                            <.dropdown
                              id="account-slack-channel-dropdown"
                              label={@selected_slack_channel_label}
                              on_select="select_account_slack_channel"
                            >
                              <:search :if={@slack_channel_options != []}>
                                <%!-- No `name`: NooraDropdown filters this input client-side only. --%>
                                <input
                                  id="account-slack-channel-search-input"
                                  type="text"
                                  placeholder={gettext("Search channels...")}
                                  data-part="search-input"
                                />
                              </:search>
                              <.dropdown_item
                                value={slack_channel_none_option_value()}
                                label={gettext("None")}
                              />
                              <.dropdown_item
                                :for={option <- @slack_channel_options}
                                value={slack_channel_option_value(option)}
                                label={slack_channel_option_label(option)}
                              />
                            </.dropdown>
                          </div>
                        </div>
                      </div>
                    </div>

                    <.line_divider />

                    <div data-part="account-settings-section">
                      <div data-part="account-settings-section-header">
                        <span data-part="account-settings-section-title">
                          {gettext("Commercial")}
                        </span>
                        <span data-part="account-settings-section-subtitle">
                          {gettext(
                            "Lifecycle, contract value, and renewal timing used across the revenue views."
                          )}
                        </span>
                      </div>

                      <div data-part="account-settings-grid">
                        <div data-part="account-settings-select">
                          <.label label={gettext("Lifecycle")} required />
                          <.select
                            id="account-segment-select"
                            name="account[segment]"
                            label={gettext("Select lifecycle")}
                            value={select_value(@account_form[:segment].value)}
                          >
                            <:item value="customer" label={gettext("Customer")} />
                            <:item value="prospect" label={gettext("Prospect")} />
                            <:item value="lead" label={gettext("Lead")} />
                          </.select>
                        </div>

                        <div data-part="account-settings-select">
                          <.label label={gettext("Deal stage")} />
                          <.select
                            id="account-deal-stage-select"
                            name="account[deal_stage]"
                            label={gettext("Select deal stage")}
                            value={select_value(@account_form[:deal_stage].value)}
                          >
                            <:item value="_none" label={gettext("None")} />
                            <:item
                              :for={stage <- DealStage.all()}
                              value={stage.key}
                              label={stage.label}
                            />
                          </.select>
                        </div>

                        <div data-part="account-settings-select">
                          <.label label={gettext("Hosting")} />
                          <.select
                            id="account-hosting-select"
                            name="account[hosting]"
                            label={gettext("Select hosting")}
                            value={select_value(@account_form[:hosting].value)}
                          >
                            <:item value="unknown" label={gettext("Not recorded")} />
                            <:item value="cloud" label={gettext("Cloud")} />
                            <:item value="self_hosted" label={gettext("Self-hosted")} />
                          </.select>
                        </div>

                        <.text_input
                          id="account-currency-input"
                          field={@account_form[:currency]}
                          type="basic"
                          label={gettext("Currency")}
                          placeholder={gettext("EUR")}
                          hint={gettext("Use a three-letter ISO currency code.")}
                          show_suffix={false}
                        />

                        <.text_input
                          id="account-current-value-input"
                          field={@account_form[:current_value]}
                          type="basic"
                          input_type="number"
                          label={gettext("Current value")}
                          step="0.01"
                          min="0"
                          show_suffix={false}
                        />

                        <.text_input
                          id="account-next-renewal-date-input"
                          field={@account_form[:next_renewal_date]}
                          type="basic"
                          input_type="date"
                          label={gettext("Next renewal")}
                          show_suffix={false}
                        />

                        <.text_input
                          id="account-poc-end-date-input"
                          field={@account_form[:poc_end_date]}
                          type="basic"
                          input_type="date"
                          label={gettext("POC end date")}
                          hint={gettext("Target date to wrap up the proof of concept.")}
                          show_suffix={false}
                        />

                        <.text_input
                          id="account-stripe-customer-id-input"
                          field={@account_form[:stripe_customer_id]}
                          type="basic"
                          label={gettext("Stripe customer ID")}
                          placeholder={gettext("cus_123")}
                          hint={gettext("Used to surface Stripe data inside Atlas.")}
                          show_suffix={false}
                        />
                      </div>
                    </div>
                  </div>
                </.form>

                <.line_divider />

                <div data-part="account-settings-section">
                  <div data-part="account-settings-section-header">
                    <span data-part="account-settings-section-title">{gettext("Handles")}</span>
                    <span data-part="account-settings-section-subtitle">
                      {gettext("Attach Tuist handles that Atlas should use for future usage joins.")}
                    </span>
                  </div>

                  <div data-part="handle-editor">
                    <div :if={@account.account_handles != []} data-part="handle-editor-list">
                      <.tag
                        :for={account_handle <- @account.account_handles}
                        id={"modal-account-handle-#{account_handle.id}"}
                        data-part="modal-handle-tag"
                        label={account_handle.handle}
                        dismissible
                        on_dismiss="remove_handle"
                        dismiss_value={to_string(account_handle.id)}
                      />
                    </div>

                    <span :if={@account.account_handles == []} data-part="handle-editor-empty">
                      {gettext("No handles linked yet.")}
                    </span>

                    <.form
                      id="account-handle-form"
                      for={@handle_form}
                      phx-submit="add_handle"
                      data-part="handle-editor-form"
                    >
                      <.text_input
                        id="account-handle-input"
                        field={@handle_form[:handle]}
                        type="basic"
                        label={gettext("New handle")}
                        placeholder={gettext("e.g. deliveryhero-production")}
                        show_suffix={false}
                      />
                      <.button
                        id="account-handle-submit"
                        label={gettext("Add Handle")}
                        size="small"
                        type="submit"
                      />
                    </.form>
                  </div>
                </div>
              </div>

              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="close_edit_account_modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      label={gettext("Save Changes")}
                      size="small"
                      type="submit"
                      form="edit-account-form"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </div>
        </:actions>
        <.card_section data-part="overview-section">
          <div
            :if={@overview_summary_processing}
            id="overview-summary-processing"
            data-part="overview-summary-processing"
            aria-live="polite"
          >
            <span data-part="overview-summary-spinner" aria-hidden="true"></span>
            <span>{gettext("Summarizing account…")}</span>
          </div>
          <div
            :if={@overview_summary_error}
            id="overview-summary-error"
            data-part="overview-summary-error"
            role="alert"
          >
            {@overview_summary_error}
          </div>
          <div id="overview-metadata-grid" data-part="metadata-grid">
            <div data-part="metadata-row">
              <.metadata_item title={gettext("Lifecycle")}>
                <.account_lifecycle_badge segment={@account.segment} />
              </.metadata_item>
              <.metadata_item title={gettext("Deal Stage")}>
                <.account_deal_stage_badge deal_stage={@account.deal_stage} />
              </.metadata_item>
              <.metadata_item title={gettext("Contract Value")}>
                {contract_value_label(@account)}
              </.metadata_item>
              <.metadata_item title={gettext("Primary Domain")}>
                {@account.primary_domain || "-"}
              </.metadata_item>
              <.metadata_item title={gettext("Parent Account")}>
                <.link
                  :if={@account.parent_account}
                  id="account-parent-link"
                  data-part="account-relationship-link"
                  navigate={~p"/commercial/sales/accounts/#{@account.parent_account.id}"}
                >
                  {@account.parent_account.name}
                </.link>
                <span :if={!@account.parent_account}>-</span>
              </.metadata_item>
            </div>
            <div data-part="metadata-row">
              <.metadata_item title={gettext("Next Renewal")}>
                {format_date(@account.next_renewal_date)}
              </.metadata_item>
              <.metadata_item title={gettext("Handles")}>
                <div :if={@account.account_handles != []} data-part="handle-badges">
                  <.badge
                    :for={account_handle <- @account.account_handles}
                    id={"account-handle-#{account_handle.id}"}
                    data-part="handle-badge"
                    label={account_handle.handle}
                    color="neutral"
                    style="light-fill"
                  />
                </div>
                <span :if={@account.account_handles == []}>-</span>
              </.metadata_item>
              <.metadata_item title={gettext("Slack Channel")}>
                <a
                  :if={@linked_slack_channel}
                  id="account-slack-channel-link"
                  data-part="slack-channel-link"
                  href={slack_channel_url(@linked_slack_channel)}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {slack_channel_label(@linked_slack_channel)}
                </a>
                <span :if={!@linked_slack_channel}>-</span>
              </.metadata_item>
              <.metadata_item title={gettext("Child Accounts")}>
                <div :if={@account.child_accounts != []} data-part="account-relationship-list">
                  <.link
                    :for={child_account <- @account.child_accounts}
                    id={"account-child-link-#{child_account.id}"}
                    data-part="account-relationship-link"
                    navigate={~p"/commercial/sales/accounts/#{child_account.id}"}
                  >
                    {child_account.name}
                  </.link>
                </div>
                <span :if={@account.child_accounts == []}>-</span>
              </.metadata_item>
            </div>
            <div
              :if={@account.overview_summary}
              id="overview-summary"
              data-part="metadata-row"
              data-variant="summary"
            >
              <div data-part="overview-summary">
                <div data-part="overview-summary-header">
                  <span data-part="metadata-title">{gettext("Summary")}</span>
                  <span :if={@account.overview_summary_generated_at} data-part="overview-summary-time">
                    <span>{gettext("Updated")}</span>
                    <.time time={@account.overview_summary_generated_at} />
                  </span>
                </div>
                <div data-part="overview-summary-body">
                  {overview_summary_html(@account.overview_summary)}
                </div>
              </div>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Feature usage")} icon="trending_up" data-part="feature-usage-card">
        <.card_section :if={not @feature_usage_view.tracked?} data-part="feature-usage-empty">
          {gettext(
            "This account is not linked to a Tuist handle yet, so feature usage is not tracked."
          )}
        </.card_section>

        <div
          :if={@feature_usage_view.tracked? and @feature_usage_view.build_systems != []}
          data-part="feature-usage-systems"
        >
          <span data-part="systems-label">{gettext("Build systems")}</span>
          <.badge :for={label <- @feature_usage_view.build_systems} color="success" dot label={label} />
        </div>

        <div
          :if={
            @feature_usage_view.tracked? and
              @feature_usage_view.continuous_integration_providers != []
          }
          data-part="feature-usage-continuous-integration"
        >
          <span data-part="continuous-integration-label">{gettext("Continuous integration")}</span>
          <.badge
            :for={label <- @feature_usage_view.continuous_integration_providers}
            color="information"
            dot
            label={label}
          />
        </div>

        <div :if={@feature_usage_view.tracked?} data-part="feature-usage-grid">
          <.card_section :for={feature <- @feature_usage_view.features} class="atlas-widget">
            <div data-part="header">
              <div data-part="legend" data-color={feature.legend_color}></div>
              <div data-part="title">
                <span data-part="label">{feature.label}</span>
              </div>
            </div>
            <div data-part="value-block">
              <span data-part="value">{feature.value}</span>
              <span data-part="caption">{feature_value_caption(feature.kind, feature.scope)}</span>
            </div>
            <div data-part="breakdown-item">
              <span data-part="label">{feature.status_label}</span>
              <span data-part="separator">·</span>
              <span data-part="label">
                {feature.events_last_24h} {feature_breakdown_caption(feature.kind)}
              </span>
            </div>
            <div data-part="breakdown-item">
              <span data-part="label">
                {feature_last_changed_label(feature.kind)} {feature.last_used_label}
              </span>
            </div>
          </.card_section>
        </div>
      </.card>

      <.card
        title={gettext("Feature interest")}
        icon="message_circle"
        data-part="feature-interest-card"
      >
        <:actions>
          <.button
            id="view-feature-interests-button"
            label={gettext("View all")}
            variant="secondary"
            size="small"
            navigate={~p"/commercial/sales/feature-interests"}
          />
        </:actions>
        <.card_section data-part="account-feature-interest-section">
          <div
            :if={@feature_interests != []}
            id="account-feature-interests"
            data-part="account-feature-interest-list"
          >
            <div
              :for={interest <- @feature_interests}
              id={"account-feature-interest-#{interest.id}"}
              data-part="account-feature-interest"
            >
              <div data-part="account-feature-interest-heading">
                <.link
                  id={"account-feature-interest-link-#{interest.id}"}
                  navigate={~p"/commercial/sales/feature-interests/#{interest.id}"}
                  data-part="account-feature-interest-title"
                >
                  {interest.title}
                </.link>
                <.badge
                  label={
                    ngettext(
                      "%{count} account",
                      "%{count} accounts",
                      interest.interest_count,
                      count: interest.interest_count
                    )
                  }
                  color="information"
                  style="light-fill"
                />
              </div>
              <p data-part="account-feature-interest-summary">
                {account_feature_interest_summary(interest)}
              </p>
              <p
                :if={account_feature_interest_notes(interest)}
                data-part="account-feature-interest-notes"
              >
                <span data-part="account-feature-interest-notes-label">
                  {gettext("Account context")}
                </span>
                {account_feature_interest_notes(interest)}
              </p>
              <div data-part="account-feature-interest-actions">
                <.link
                  :if={account_feature_interest_event(interest)}
                  id={"account-feature-interest-source-#{interest.id}"}
                  navigate={
                    "/commercial/sales/accounts/#{@account.id}#timeline-event-#{account_feature_interest_event(interest).id}"
                  }
                  data-part="account-feature-interest-source"
                >
                  {gettext("Open source event")}
                </.link>
                <.link
                  :if={
                    is_nil(account_feature_interest_event(interest)) &&
                      account_feature_interest_thread(interest)
                  }
                  id={"account-feature-interest-source-#{interest.id}"}
                  navigate={~p"/commercial/support/#{account_feature_interest_thread(interest).id}"}
                  data-part="account-feature-interest-source"
                >
                  {gettext("Open source conversation")}
                </.link>
                <.button
                  id={"edit-feature-interest-notes-#{interest.id}"}
                  label={gettext("Edit context")}
                  variant="secondary"
                  size="small"
                  type="button"
                  phx-click="open_feature_interest_notes_modal"
                  phx-value-id={account_feature_interest(interest).id}
                />
              </div>
            </div>
          </div>
          <.account_empty_state
            :if={@feature_interests == []}
            id="account-feature-interests-empty"
            title={gettext("No feature interest recorded")}
            subtitle={gettext("Record requests from timeline events to see them here.")}
          />
        </.card_section>
      </.card>

      <.card title={gettext("Evaluations")} icon="checkup_list" data-part="account-pocs-card">
        <.card_section data-part="account-pocs-section">
          <.table
            :if={@pocs != []}
            id="account-pocs-table"
            rows={@pocs}
            row_key={fn poc -> "account-poc-#{poc.id}" end}
            row_navigate={fn poc -> ~p"/commercial/sales/pocs/#{poc.id}" end}
          >
            <:col :let={poc} label={gettext("Evaluation")}>
              <.text_cell label={poc.title} />
            </:col>
            <:col :let={poc} label={gettext("Status")}>
              <.badge_cell
                label={Phoenix.Naming.humanize(poc.status)}
                color={evaluation_status_color(poc.status)}
                style="light-fill"
              />
            </:col>
            <:col :let={poc} label={gettext("Hosting")}>
              <.text_cell label={Phoenix.Naming.humanize(poc.hosting)} />
            </:col>
            <:col :let={poc} label={gettext("Started")}>
              <.text_cell label={format_date(poc.starts_on)} />
            </:col>
          </.table>
          <.account_empty_state
            :if={@pocs == []}
            id="account-pocs-empty"
            title={gettext("No evaluations yet")}
            subtitle={gettext("Evaluations for this account will appear here.")}
          />
        </.card_section>
      </.card>

      <.card
        :if={@account.documents != []}
        title={gettext("Documents")}
        icon="file"
        data-part="documents-card"
      >
        <.card_section data-part="documents-section">
          <div id="account-documents-list" data-part="document-list">
            <.link
              :for={document <- @account.documents}
              id={"account-document-#{document.id}"}
              data-part="document-item"
              navigate={~p"/library/documents/#{document.id}"}
            >
              <span data-part="document-title">{document.title}</span>
              <span data-part="document-meta">
                {account_document_meta(document)}
              </span>
            </.link>
          </div>
        </.card_section>
      </.card>

      <.card title={gettext("Contacts")} icon="users" data-part="contacts-card">
        <:actions>
          <div data-part="contacts-card-actions">
            <.button
              id="add-contact-button"
              label={gettext("Add Contact")}
              variant="secondary"
              size="small"
              type="button"
              phx-click="open_new_contact_modal"
            />

            <.modal
              id="contact-modal"
              title={gettext("Contact")}
              description={
                gettext(
                  "Store the relationship details Atlas should remember, including local notes about patterns, preferences, and behaviors."
                )
              }
              header_type="icon"
              header_size="small"
              on_dismiss="close_contact_modal"
            >
              <:header_icon><.user /></:header_icon>
              <:trigger :let={modal_attrs}>
                <button id="contact-modal-trigger" type="button" hidden {modal_attrs}></button>
              </:trigger>

              <div data-part="contact-modal-content">
                <.form id="contact-form" for={@contact_form} phx-submit="save_contact">
                  <div data-part="contact-modal-form">
                    <div data-part="contact-modal-grid">
                      <.text_input
                        id="contact-full-name-input"
                        field={@contact_form[:full_name]}
                        type="basic"
                        label={gettext("Full name")}
                        required
                        show_required
                        show_suffix={false}
                      />
                      <.text_input
                        id="contact-title-input"
                        field={@contact_form[:title]}
                        type="basic"
                        label={gettext("Role or title")}
                        placeholder={gettext("Finance lead, requester, champion...")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="contact-email-input"
                        field={@contact_form[:email]}
                        type="email"
                        label={gettext("Email")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="contact-linkedin-input"
                        field={@contact_form[:linkedin_url]}
                        type="basic"
                        label={gettext("LinkedIn profile")}
                        placeholder={gettext("https://www.linkedin.com/in/...")}
                        show_suffix={false}
                      />
                      <div data-part="contact-modal-grid-full">
                        <.text_area
                          id="contact-notes-input"
                          field={@contact_form[:notes]}
                          label={gettext("Notes")}
                          placeholder={
                            gettext(
                              "Patterns, behaviors, preferences, or follow-up guidance from conversations"
                            )
                          }
                          rows={5}
                          max_length={800}
                        />
                      </div>
                    </div>
                  </div>
                </.form>
              </div>

              <:footer>
                <.modal_footer>
                  <:action :if={@selected_contact}>
                    <.button
                      id="delete-contact-button"
                      label={gettext("Delete")}
                      variant="destructive"
                      size="small"
                      type="button"
                      phx-click="delete_contact"
                      data-confirm={gettext("Delete this contact? This cannot be undone.")}
                    />
                  </:action>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="close_contact_modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      label={contact_modal_submit_label(@contact_modal_mode, @selected_contact)}
                      size="small"
                      type="submit"
                      form="contact-form"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </div>
        </:actions>
        <.card_section data-part="contacts-section">
          <div :if={@account.contacts != []} id="account-contacts-list" data-part="contact-list">
            <div
              :for={contact <- @account.contacts}
              id={"contact-#{contact.id}"}
              data-part="contact-item"
            >
              <div data-part="contact-main">
                <.avatar
                  id={"contact-avatar-#{contact.id}"}
                  name={contact.full_name}
                  color={contact_avatar_color(contact)}
                  size="small"
                />
                <div data-part="contact-content">
                  <div data-part="contact-heading">
                    <span data-part="contact-name">{contact.full_name}</span>
                  </div>
                  <span :if={contact.title} data-part="contact-title">{contact.title}</span>
                  <a :if={contact.email} data-part="contact-email" href={"mailto:" <> contact.email}>
                    {contact.email}
                  </a>
                  <a
                    :if={contact.linkedin_url}
                    data-part="contact-email"
                    href={contact.linkedin_url}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {gettext("LinkedIn profile")}
                  </a>
                </div>
              </div>

              <div data-part="contact-notes-group">
                <span data-part="contact-notes-label">{gettext("Notes")}</span>
                <p data-part="contact-notes">
                  {contact.notes ||
                    gettext(
                      "No notes yet. Capture patterns, preferences, or behaviors Atlas should remember."
                    )}
                </p>
              </div>

              <div data-part="contact-action">
                <.button
                  id={"contact-history-button-#{contact.id}"}
                  label={gettext("History")}
                  variant="secondary"
                  size="small"
                  navigate={~p"/commercial/gtm/outreach/#{contact.id}"}
                />
                <.button
                  id={"edit-contact-button-#{contact.id}"}
                  label={gettext("Edit")}
                  variant="secondary"
                  size="small"
                  type="button"
                  phx-click="open_edit_contact_modal"
                  phx-value-id={contact.id}
                />
              </div>
            </div>
          </div>

          <.account_empty_state
            :if={@account.contacts == []}
            title={gettext("No contacts yet")}
            subtitle={
              gettext(
                "Imported contacts will appear here, and you can also add your own people with local notes."
              )
            }
          />
        </.card_section>
      </.card>

      <.card title={gettext("Billing & Address")} icon="building" data-part="billing-card">
        <:actions>
          <.modal
            id="edit-billing-modal"
            title={gettext("Billing & Address")}
            description={gettext("Address, billing identifiers, and contract signatory.")}
            header_type="icon"
            header_size="small"
            on_dismiss="close_edit_billing_modal"
          >
            <:header_icon><.atom /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="edit-billing-button"
                label={gettext("Edit")}
                variant="secondary"
                size="small"
                {modal_attrs}
              />
            </:trigger>

            <div data-part="account-settings-modal-content">
              <.form id="edit-billing-form" for={@account_form} phx-submit="save_account">
                <div data-part="account-settings-sections">
                  <div data-part="account-settings-section">
                    <div data-part="account-settings-section-header">
                      <span data-part="account-settings-section-title">{gettext("Address")}</span>
                      <span data-part="account-settings-section-subtitle">
                        {gettext("Billing address used on invoices and contracts.")}
                      </span>
                    </div>

                    <.inputs_for :let={address_form} field={@account_form[:address]}>
                      <div data-part="account-settings-grid">
                        <.text_input
                          id="account-address-street-input"
                          field={address_form[:street]}
                          type="basic"
                          label={gettext("Street")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-address-city-input"
                          field={address_form[:city]}
                          type="basic"
                          label={gettext("City")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-address-zip-input"
                          field={address_form[:zip]}
                          type="basic"
                          label={gettext("Zip")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-address-country-input"
                          field={address_form[:country]}
                          type="basic"
                          label={gettext("Country")}
                          show_suffix={false}
                        />
                      </div>
                    </.inputs_for>
                  </div>

                  <.line_divider />

                  <div data-part="account-settings-section">
                    <div data-part="account-settings-section-header">
                      <span data-part="account-settings-section-title">{gettext("Billing")}</span>
                      <span data-part="account-settings-section-subtitle">
                        {gettext("Tax identifiers and billing recipients used on invoices.")}
                      </span>
                    </div>

                    <.inputs_for :let={billing_form} field={@account_form[:billing]}>
                      <div data-part="account-settings-grid">
                        <.text_input
                          id="account-billing-tax-id-input"
                          field={billing_form[:tax_id]}
                          type="basic"
                          label={gettext("Tax ID")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-billing-vat-id-input"
                          field={billing_form[:vat_id]}
                          type="basic"
                          label={gettext("VAT ID")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-billing-sold-to-input"
                          field={billing_form[:sold_to]}
                          type="basic"
                          label={gettext("Sold to")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-billing-bill-to-input"
                          field={billing_form[:bill_to]}
                          type="basic"
                          label={gettext("Bill to")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-billing-email-input"
                          field={billing_form[:email]}
                          type="email"
                          label={gettext("Email")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-billing-phone-input"
                          field={billing_form[:phone]}
                          type="basic"
                          label={gettext("Phone")}
                          show_suffix={false}
                        />
                      </div>
                    </.inputs_for>
                  </div>

                  <.line_divider />

                  <div data-part="account-settings-section">
                    <div data-part="account-settings-section-header">
                      <span data-part="account-settings-section-title">{gettext("Signatory")}</span>
                      <span data-part="account-settings-section-subtitle">
                        {gettext("Person signing the contract on behalf of the customer.")}
                      </span>
                    </div>

                    <.inputs_for :let={signatory_form} field={@account_form[:signatory]}>
                      <div data-part="account-settings-grid">
                        <.text_input
                          id="account-signatory-name-input"
                          field={signatory_form[:name]}
                          type="basic"
                          label={gettext("Name")}
                          show_suffix={false}
                        />
                        <.text_input
                          id="account-signatory-title-input"
                          field={signatory_form[:title]}
                          type="basic"
                          label={gettext("Title")}
                          show_suffix={false}
                        />
                      </div>
                    </.inputs_for>
                  </div>
                </div>
              </.form>
            </div>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="close_edit_billing_modal"
                  />
                </:action>
                <:action>
                  <.button
                    label={gettext("Save Changes")}
                    size="small"
                    type="submit"
                    form="edit-billing-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </:actions>
        <.card_section data-part="billing-section">
          <div data-part="metadata-grid">
            <div :if={!Address.empty?(@account.address)} data-part="metadata-row">
              <.metadata_item title={gettext("Street")}>
                {address_value(@account.address, :street)}
              </.metadata_item>
              <.metadata_item title={gettext("City")}>
                {address_value(@account.address, :city)}
              </.metadata_item>
              <.metadata_item title={gettext("Zip")}>
                {address_value(@account.address, :zip)}
              </.metadata_item>
              <.metadata_item title={gettext("Country")}>
                {address_value(@account.address, :country)}
              </.metadata_item>
            </div>

            <div :if={!Billing.empty?(@account.billing)} data-part="metadata-row">
              <.metadata_item title={gettext("Tax ID")}>
                {billing_value(@account.billing, :tax_id)}
              </.metadata_item>
              <.metadata_item title={gettext("VAT ID")}>
                {billing_value(@account.billing, :vat_id)}
              </.metadata_item>
              <.metadata_item title={gettext("Sold to")}>
                {billing_value(@account.billing, :sold_to)}
              </.metadata_item>
              <.metadata_item title={gettext("Bill to")}>
                {billing_value(@account.billing, :bill_to)}
              </.metadata_item>
              <.metadata_item title={gettext("Email")}>
                {billing_value(@account.billing, :email)}
              </.metadata_item>
              <.metadata_item title={gettext("Phone")}>
                {billing_value(@account.billing, :phone)}
              </.metadata_item>
            </div>

            <div :if={!Signatory.empty?(@account.signatory)} data-part="metadata-row">
              <.metadata_item title={gettext("Signatory")}>
                {signatory_value(@account.signatory, :name)}
              </.metadata_item>
              <.metadata_item title={gettext("Signatory title")}>
                {signatory_value(@account.signatory, :title)}
              </.metadata_item>
            </div>
          </div>

          <.account_empty_state
            :if={!show_billing_card?(@account)}
            title={gettext("No billing or address details yet")}
            subtitle={
              gettext(
                "Edit the account to add address, billing identifiers, and the contract signatory."
              )
            }
          />
        </.card_section>
      </.card>

      <.card title={gettext("Contract Terms")} icon="file" data-part="terms-card">
        <:actions>
          <div data-part="terms-card-actions">
            <.button
              id="add-term-button"
              label={gettext("Add Term")}
              variant="secondary"
              size="small"
              type="button"
              phx-click="open_new_term_modal"
            />

            <.modal
              id="term-modal"
              title={gettext("Contract Term")}
              description={
                gettext("Capture the contract term as it was signed: dates, seats, pricing, and PO.")
              }
              header_type="icon"
              header_size="small"
              on_dismiss="close_term_modal"
            >
              <:header_icon><.atom /></:header_icon>
              <:trigger :let={modal_attrs}>
                <button id="term-modal-trigger" type="button" hidden {modal_attrs}></button>
              </:trigger>

              <div data-part="term-modal-content">
                <.form id="term-form" for={@term_form} phx-submit="save_term">
                  <div data-part="account-settings-grid">
                    <div data-part="account-settings-select">
                      <.label label={gettext("Payment")} required />
                      <.select
                        id="term-payment-select"
                        name="term[payment]"
                        label={gettext("Select cadence")}
                        value={select_value(@term_form[:payment].value)}
                      >
                        <:item value="monthly" label={gettext("Monthly")} />
                        <:item value="yearly" label={gettext("Yearly")} />
                        <:item value="whole-term" label={gettext("Whole term")} />
                      </.select>
                    </div>

                    <.text_input
                      id="term-start-date-input"
                      field={@term_form[:start_date]}
                      type="basic"
                      input_type="date"
                      label={gettext("Start date")}
                      required
                      show_required
                      show_suffix={false}
                    />

                    <.text_input
                      id="term-end-date-input"
                      field={@term_form[:end_date]}
                      type="basic"
                      input_type="date"
                      label={gettext("End date")}
                      show_suffix={false}
                    />

                    <.text_input
                      id="term-seats-input"
                      field={@term_form[:seats]}
                      type="basic"
                      input_type="number"
                      label={gettext("Seats")}
                      min="0"
                      step="1"
                      show_suffix={false}
                    />

                    <.text_input
                      id="term-price-per-seat-input"
                      field={@term_form[:price_per_seat]}
                      type="basic"
                      input_type="number"
                      label={gettext("Price per seat")}
                      min="0"
                      step="0.01"
                      show_suffix={false}
                    />

                    <.text_input
                      id="term-discount-input"
                      field={@term_form[:discount]}
                      type="basic"
                      input_type="number"
                      label={gettext("Discount")}
                      min="0"
                      step="0.01"
                      show_suffix={false}
                    />

                    <.text_input
                      id="term-total-input"
                      field={@term_form[:total]}
                      type="basic"
                      input_type="number"
                      label={gettext("Total")}
                      required
                      show_required
                      min="0"
                      step="0.01"
                      show_suffix={false}
                    />

                    <div data-part="account-settings-select">
                      <.label label={gettext("Currency")} />
                      <.select
                        id="term-currency-select"
                        name="term[currency]"
                        label={gettext("Defaults to account currency")}
                        value={select_value(@term_form[:currency].value)}
                      >
                        <:item value="EUR" label="EUR" />
                        <:item value="USD" label="USD" />
                      </.select>
                    </div>

                    <.text_input
                      id="term-renewal-notice-weeks-input"
                      field={@term_form[:renewal_notice_weeks]}
                      type="basic"
                      input_type="number"
                      label={gettext("Renewal notice (weeks)")}
                      min="1"
                      step="1"
                      show_suffix={false}
                    />

                    <.text_input
                      id="term-po-number-input"
                      field={@term_form[:po_number]}
                      type="basic"
                      label={gettext("PO number")}
                      show_suffix={false}
                    />

                    <div data-part="account-settings-select">
                      <.label label={gettext("Deployment")} />
                      <.select
                        id="term-on-premise-select"
                        name="term[on_premise]"
                        label={gettext("Select deployment")}
                        value={to_string(@term_form[:on_premise].value || false)}
                      >
                        <:item value="false" label={gettext("Cloud")} />
                        <:item value="true" label={gettext("On-premise")} />
                      </.select>
                    </div>
                  </div>
                </.form>
              </div>

              <:footer>
                <.modal_footer>
                  <:action :if={@selected_term}>
                    <.button
                      id="delete-term-button"
                      label={gettext("Delete")}
                      variant="destructive"
                      size="small"
                      type="button"
                      phx-click="delete_term"
                      data-confirm={gettext("Delete this term? This cannot be undone.")}
                    />
                  </:action>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="close_term_modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      label={term_modal_submit_label(@term_modal_mode)}
                      size="small"
                      type="submit"
                      form="term-form"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </div>
        </:actions>
        <.card_section data-part="terms-section">
          <.table :if={@account.terms != []} id="account-terms-table" rows={@account.terms}>
            <:col :let={term} label={gettext("Term")}>
              <.text_cell label={term_window(term)} />
            </:col>
            <:col :let={term} label={gettext("Payment")}>
              <.text_cell label={term.payment} />
            </:col>
            <:col :let={term} label={gettext("Seats")}>
              <.text_cell label={term_seats(term)} />
            </:col>
            <:col :let={term} label={gettext("Per seat")}>
              <.text_cell label={
                Amounts.format_or_nil(term.price_per_seat, term_currency(term, @account)) || "-"
              } />
            </:col>
            <:col :let={term} label={gettext("Discount")}>
              <.text_cell label={
                Amounts.format_or_nil(term.discount, term_currency(term, @account)) || "-"
              } />
            </:col>
            <:col :let={term} label={gettext("Total")}>
              <.text_cell label={
                Amounts.format_or_nil(term.total, term_currency(term, @account)) || "-"
              } />
            </:col>
            <:col :let={term} label={gettext("Deployment")}>
              <.text_cell label={
                if term.on_premise, do: gettext("On-premise"), else: gettext("Cloud")
              } />
            </:col>
            <:col :let={term} label={gettext("PO")}>
              <.text_cell label={term.po_number || "-"} />
            </:col>
            <:col :let={term} label="">
              <.button_cell>
                <:button>
                  <div data-part="term-actions-cell">
                    <.dropdown id={"term-actions-#{term.id}"} icon_only size="medium">
                      <:icon><.dots_vertical /></:icon>

                      <.dropdown_item
                        id={"edit-term-button-#{term.id}"}
                        value="edit"
                        label={gettext("Edit")}
                        on_click="open_edit_term_modal"
                        phx-value-id={term.id}
                      >
                        <:left_icon><.pencil /></:left_icon>
                      </.dropdown_item>
                      <.dropdown_item
                        id={"renew-term-button-#{term.id}"}
                        value="renew"
                        label={gettext("Renew")}
                        on_click="renew_term"
                        phx-value-id={term.id}
                      >
                        <:left_icon><.reload /></:left_icon>
                      </.dropdown_item>
                    </.dropdown>
                  </div>
                </:button>
              </.button_cell>
            </:col>
          </.table>

          <.account_empty_state
            :if={@account.terms == []}
            title={gettext("No contract terms yet")}
            subtitle={gettext("Add the first signed term so renewal and revenue views can use it.")}
          />
        </.card_section>
      </.card>

      <.card title={gettext("Service Levels")} icon="file" data-part="service-levels-card">
        <.card_section data-part="service-levels-section">
          <div
            :if={@account.service_levels != []}
            id="account-service-levels"
            data-part="service-level-list"
          >
            <div
              :for={service_level <- @account.service_levels}
              id={"account-service-level-#{service_level.id}"}
              data-part="service-level-item"
            >
              <div data-part="service-level-content">
                <div data-part="service-level-heading">
                  <span data-part="service-level-name">{service_level.name}</span>
                  <span data-part="service-level-category">
                    {service_level_category_label(service_level.category)}
                  </span>
                </div>

                <p data-part="service-level-target">{service_level.target}</p>

                <div data-part="service-level-meta">
                  <span :if={service_level.measurement_window}>
                    {service_level.measurement_window}
                  </span>
                  <span :if={service_level.applies_from || service_level.applies_until}>
                    {service_level_window(service_level)}
                  </span>
                  <span :if={service_level.source_page}>
                    {gettext("Page %{page}", page: service_level.source_page)}
                  </span>
                  <.link
                    :if={service_level.document_id}
                    id={"service-level-document-#{service_level.id}"}
                    data-part="service-level-document-link"
                    navigate={~p"/library/documents/#{service_level.document_id}"}
                  >
                    {service_level_document_title(service_level)}
                  </.link>
                </div>

                <div
                  :if={service_level.service_credit || service_level.exclusions}
                  data-part="service-level-details"
                >
                  <div :if={service_level.service_credit} data-part="service-level-detail">
                    <span data-part="service-level-detail-label">{gettext("Credit")}</span>
                    <span data-part="service-level-detail-value">{service_level.service_credit}</span>
                  </div>
                  <div :if={service_level.exclusions} data-part="service-level-detail">
                    <span data-part="service-level-detail-label">{gettext("Exclusions")}</span>
                    <span data-part="service-level-detail-value">{service_level.exclusions}</span>
                  </div>
                </div>

                <p :if={service_level.source_excerpt} data-part="service-level-excerpt">
                  {service_level.source_excerpt}
                </p>
              </div>
            </div>
          </div>

          <.account_empty_state
            :if={@account.service_levels == []}
            id="account-service-levels-empty"
            title={gettext("No service levels extracted yet")}
            subtitle={
              gettext("Atlas checks linked contract documents and stores any signed SLA commitments.")
            }
          />
        </.card_section>
      </.card>

      <.card
        :if={show_invoices_card?(@account, @invoices_view)}
        title={gettext("Invoices")}
        icon="file"
        data-part="invoices-card"
      >
        <.card_section data-part="invoices-section">
          <div :if={@invoices_view.status == :error} data-part="invoices-error">
            {gettext("Could not load invoices from Stripe right now. Try again shortly.")}
          </div>

          <.table
            :if={@invoices_view.invoices != []}
            id="account-invoices-table"
            rows={@invoices_view.invoices}
          >
            <:col :let={invoice} label={gettext("Date")}>
              <.text_cell label={format_date(invoice_date(invoice))} />
            </:col>
            <:col :let={invoice} label={gettext("Number")}>
              <.text_cell label={invoice_number(invoice)} />
            </:col>
            <:col :let={invoice} label={gettext("Amount")}>
              <.text_cell label={
                Amounts.format_or_nil(invoice_amount(invoice), invoice_currency(invoice)) || "-"
              } />
            </:col>
            <:col :let={invoice} label={gettext("Status")}>
              <.text_cell label={invoice.status || "-"} />
            </:col>
            <:col :let={invoice} label={gettext("Reference")}>
              <.button
                :if={invoice_url(invoice)}
                label={gettext("Open in Stripe")}
                variant="secondary"
                size="small"
                href={invoice_url(invoice)}
                target="_blank"
                rel="noopener noreferrer"
              >
                <:icon_right><.icon name="external_link" /></:icon_right>
              </.button>
              <span :if={!invoice_url(invoice)}>-</span>
            </:col>
          </.table>

          <.pagination_group
            :if={@invoices_view.total_pages > 1}
            current_page={@invoices_view.page}
            number_of_pages={@invoices_view.total_pages}
            page_patch={fn page -> "?#{Query.put(@uri.query, "invoices-page", page)}" end}
          />

          <.account_empty_state
            :if={@invoices_view.invoices == [] and @invoices_view.status == :ok}
            title={empty_invoices_title(@invoices_view, @account)}
            subtitle={empty_invoices_subtitle(@invoices_view, @account)}
          />
        </.card_section>
      </.card>

      <.card
        title={gettext("Account nudges")}
        icon="bell"
        data-part="account-nudges-card"
      >
        <.card_section data-part="account-nudges-section">
          <div :if={@nudges != []} id="account-nudges-table" data-part="account-nudges-table">
            <.table id="account-nudges" rows={@nudges} row_key={fn n -> "nudge-row-#{n.id}" end}>
              <:col :let={nudge} label={gettext("Nudge")}>
                <.text_and_description_cell
                  label={nudge.title}
                  description={nudge.rationale}
                />
              </:col>
              <:col :let={nudge} label={gettext("Signal")}>
                <.badge_cell label={nudge.signal} color="information" style="light-fill" />
              </:col>
              <:col :let={nudge} label={gettext("State")}>
                <.badge_cell
                  label={nudge_state_label(nudge, nudge_stage(nudge))}
                  color={nudge_state_color(nudge, nudge_stage(nudge))}
                  style="light-fill"
                />
              </:col>
              <:col :let={nudge} label={gettext("Opened")}>
                <.text_cell label={format_nudge_timestamp(nudge.inserted_at)} />
              </:col>
              <:col :let={nudge} label="">
                <.button_cell :if={nudge.state == "proposed"}>
                  <:button>
                    <.button_dropdown
                      id={"nudge-actions-#{nudge.id}"}
                      label={gettext("Claim")}
                      size="medium"
                      align="end"
                      phx-click="claim_nudge"
                      phx-value-id={nudge.id}
                    >
                      <.dropdown_item
                        id={"dismiss-nudge-#{nudge.id}"}
                        value="dismiss"
                        label={gettext("Dismiss")}
                        on_click="open_dismiss_nudge_modal"
                        phx-value-id={nudge.id}
                      >
                        <:left_icon><.circle_x /></:left_icon>
                      </.dropdown_item>
                    </.button_dropdown>
                  </:button>
                </.button_cell>
                <.button_cell :if={nudge.state == "claimed"}>
                  <:button>
                    <.button_dropdown
                      id={"nudge-actions-#{nudge.id}"}
                      label={gettext("Send")}
                      size="medium"
                      align="end"
                      phx-click="send_nudge"
                      phx-value-id={nudge.id}
                    >
                      <.dropdown_item
                        id={"release-nudge-#{nudge.id}"}
                        value="release"
                        label={gettext("Release")}
                        on_click="release_nudge"
                        phx-value-id={nudge.id}
                      >
                        <:left_icon><.reload /></:left_icon>
                      </.dropdown_item>
                      <.dropdown_item
                        id={"dismiss-claimed-nudge-#{nudge.id}"}
                        value="dismiss"
                        label={gettext("Dismiss")}
                        on_click="open_dismiss_nudge_modal"
                        phx-value-id={nudge.id}
                      >
                        <:left_icon><.circle_x /></:left_icon>
                      </.dropdown_item>
                    </.button_dropdown>
                  </:button>
                </.button_cell>
                <.button_cell :if={nudge.state == "sent" and nudge_stage(nudge) == :failed}>
                  <:button>
                    <.button_dropdown
                      id={"nudge-actions-#{nudge.id}"}
                      label={gettext("Retry")}
                      size="medium"
                      align="end"
                      phx-click="retry_nudge"
                      phx-value-id={nudge.id}
                    >
                      <.dropdown_item
                        id={"dismiss-sent-nudge-#{nudge.id}"}
                        value="dismiss"
                        label={gettext("Dismiss")}
                        on_click="open_dismiss_nudge_modal"
                        phx-value-id={nudge.id}
                      >
                        <:left_icon><.circle_x /></:left_icon>
                      </.dropdown_item>
                    </.button_dropdown>
                  </:button>
                </.button_cell>
              </:col>
            </.table>
          </div>

          <.account_empty_state
            :if={@nudges == []}
            id="account-nudges-empty"
            title={gettext("No nudges yet")}
            subtitle={
              gettext(
                "Signals will drop a card here (and in Slack) when the account crosses a threshold worth reaching out about."
              )
            }
          />

          <.modal
            id="dismiss-nudge-modal"
            title={gettext("Dismiss nudge")}
            description={
              gettext("Add a short reason. This helps tune thresholds and shows on the account.")
            }
            header_type="icon"
            header_size="small"
            on_dismiss="close_dismiss_nudge_modal"
          >
            <:header_icon><.circle_x /></:header_icon>
            <:trigger :let={modal_attrs}>
              <button id="dismiss-nudge-modal-trigger" type="button" hidden {modal_attrs}></button>
            </:trigger>

            <div data-part="dismiss-nudge-modal-content">
              <.form
                id="dismiss-nudge-form"
                for={@dismiss_nudge_form}
                phx-submit="dismiss_nudge"
              >
                <.text_area
                  id="dismiss-nudge-reason-input"
                  field={@dismiss_nudge_form[:reason]}
                  label={gettext("Reason")}
                  placeholder={gettext("Not the right moment; team already knows; ...")}
                  rows={4}
                  max_length={500}
                  required
                />
              </.form>
            </div>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    id="cancel-dismiss-nudge-button"
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="close_dismiss_nudge_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="confirm-dismiss-nudge-button"
                    label={gettext("Dismiss")}
                    variant="destructive"
                    size="small"
                    type="submit"
                    form="dismiss-nudge-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </.card_section>
      </.card>

      <.card
        :if={false}
        title={gettext("Customer Outcomes")}
        icon="checkup_list"
        data-part="outcomes-card"
      >
        <:actions>
          <div data-part="outcomes-card-actions">
            <.button
              id="suggest-outcomes-button"
              label={
                if @outcome_proposals_processing,
                  do: gettext("Reviewing evidence…"),
                  else: gettext("Suggest Outcomes")
              }
              variant="secondary"
              size="small"
              type="button"
              phx-click="generate_outcome_proposals"
              disabled={@outcome_proposals_processing}
            />
            <.button
              id="add-outcome-button"
              label={gettext("Add Outcome")}
              variant="secondary"
              size="small"
              type="button"
              phx-click="open_new_outcome_modal"
            />

            <.modal
              id="outcome-modal"
              title={gettext("Customer Outcome")}
              description={gettext("Define the measurable result this account is trying to achieve.")}
              header_type="icon"
              header_size="small"
              on_dismiss="close_outcome_modal"
            >
              <:header_icon><.icon name="checkup_list" /></:header_icon>
              <:trigger :let={modal_attrs}>
                <button id="outcome-modal-trigger" type="button" hidden {modal_attrs}></button>
              </:trigger>

              <div data-part="outcome-modal-content">
                <.form id="outcome-form" for={@outcome_form} phx-submit="save_outcome">
                  <div data-part="outcome-modal-grid">
                    <.text_input
                      id="outcome-title-input"
                      field={@outcome_form[:title]}
                      type="basic"
                      label={gettext("Title")}
                      required
                      show_required
                      show_suffix={false}
                    />
                    <div data-part="outcome-modal-select">
                      <.label label={gettext("Motion")} required />
                      <.select
                        id="outcome-motion-select"
                        name="outcome[motion]"
                        label={gettext("Select motion")}
                        value={select_value(@outcome_form[:motion].value)}
                      >
                        <:item value="evaluation" label={gettext("Evaluation")} />
                        <:item value="adoption" label={gettext("Adoption")} />
                        <:item value="expansion" label={gettext("Expansion")} />
                        <:item value="renewal" label={gettext("Renewal")} />
                        <:item value="recovery" label={gettext("Recovery")} />
                      </.select>
                    </div>
                    <.text_input
                      id="outcome-target-date-input"
                      field={@outcome_form[:target_date]}
                      type="basic"
                      input_type="date"
                      label={gettext("Target date")}
                      show_suffix={false}
                    />
                    <.text_input
                      id="outcome-success-measure-input"
                      field={@outcome_form[:success_measure]}
                      type="basic"
                      label={gettext("Success measure")}
                      placeholder={gettext("For example: weekly active developers")}
                      show_suffix={false}
                    />
                    <.text_input
                      id="outcome-baseline-input"
                      field={@outcome_form[:baseline]}
                      type="basic"
                      label={gettext("Baseline")}
                      placeholder={gettext("Current state")}
                      show_suffix={false}
                    />
                    <.text_input
                      id="outcome-target-input"
                      field={@outcome_form[:target]}
                      type="basic"
                      label={gettext("Target")}
                      placeholder={gettext("Desired state")}
                      show_suffix={false}
                    />
                    <div data-part="outcome-modal-grid-full">
                      <.text_area
                        id="outcome-description-input"
                        field={@outcome_form[:description]}
                        label={gettext("Why this matters")}
                        placeholder={
                          gettext(
                            "Describe the customer's desired result and the evidence behind it."
                          )
                        }
                        rows={5}
                        max_length={2000}
                      />
                    </div>
                  </div>
                </.form>
              </div>

              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="close_outcome_modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      label={gettext("Add Outcome")}
                      size="small"
                      type="submit"
                      form="outcome-form"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>

            <.modal
              :if={@selected_outcome}
              id="outcome-review-modal"
              title={gettext("Review Outcome")}
              description={@selected_outcome.title}
              header_type="icon"
              header_size="small"
              on_dismiss="close_outcome_review_modal"
            >
              <:header_icon><.icon name="chart_dots" /></:header_icon>
              <:trigger :let={modal_attrs}>
                <button id="outcome-review-modal-trigger" type="button" hidden {modal_attrs}></button>
              </:trigger>
              <div data-part="outcome-review-modal-content">
                <.form
                  id="outcome-review-form"
                  for={@outcome_review_form}
                  phx-submit="save_outcome_review"
                >
                  <div data-part="outcome-modal-grid">
                    <div data-part="outcome-modal-select">
                      <.label label={gettext("Health")} required />
                      <.select
                        id="outcome-review-health-select"
                        name="outcome_review[health]"
                        label={gettext("Select health")}
                        value={select_value(@outcome_review_form[:health].value)}
                      >
                        <:item value="on_track" label={gettext("On track")} />
                        <:item value="at_risk" label={gettext("At risk")} />
                        <:item value="off_track" label={gettext("Off track")} />
                        <:item value="unknown" label={gettext("Unknown")} />
                      </.select>
                    </div>
                    <div data-part="outcome-modal-grid-full">
                      <.text_area
                        id="outcome-review-summary-input"
                        field={@outcome_review_form[:summary]}
                        label={gettext("Evidence-based review")}
                        placeholder={gettext("What changed, and what evidence supports this health?")}
                        rows={5}
                        max_length={3000}
                        required
                      />
                    </div>
                    <div data-part="outcome-modal-grid-full">
                      <.text_area
                        id="outcome-review-recommendation-input"
                        field={@outcome_review_form[:recommendation]}
                        label={gettext("Recommended next move")}
                        placeholder={gettext("The single best move to improve the outcome.")}
                        rows={3}
                        max_length={1500}
                      />
                    </div>
                  </div>
                </.form>
              </div>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="close_outcome_review_modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      label={gettext("Save Review")}
                      size="small"
                      type="submit"
                      form="outcome-review-form"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>

            <.modal
              :if={@selected_outcome_proposal}
              id="outcome-proposal-modal"
              title={gettext("Review Outcome Suggestion")}
              description={outcome_proposal_subject(@selected_outcome_proposal)}
              header_type="icon"
              header_size="small"
              on_dismiss="close_outcome_proposal_modal"
            >
              <:header_icon><.icon name="checkup_list" /></:header_icon>
              <:trigger :let={modal_attrs}>
                <button id="outcome-proposal-modal-trigger" type="button" hidden {modal_attrs}>
                </button>
              </:trigger>

              <div data-part="outcome-proposal-modal-content">
                <div data-part="outcome-proposal-context">
                  <div data-part="outcome-proposal-heading">
                    <.badge
                      label={outcome_proposal_type_label(@selected_outcome_proposal)}
                      color="information"
                      style="light-fill"
                    />
                    <span data-part="outcome-proposal-confidence">
                      {gettext("%{confidence} confidence",
                        confidence: outcome_proposal_confidence(@selected_outcome_proposal)
                      )}
                    </span>
                  </div>
                  <p data-part="outcome-proposal-rationale">
                    {@selected_outcome_proposal.rationale}
                  </p>
                  <div data-part="outcome-proposal-evidence">
                    <span data-part="outcome-meta-label">{gettext("Evidence")}</span>
                    <ul>
                      <li :for={item <- outcome_proposal_evidence(@selected_outcome_proposal)}>
                        {outcome_proposal_evidence_observation(item)}
                      </li>
                    </ul>
                  </div>
                </div>

                <.form
                  id="outcome-proposal-form"
                  for={@outcome_proposal_form}
                  phx-submit="approve_outcome_proposal"
                >
                  <div data-part="outcome-modal-grid">
                    <%= if @selected_outcome_proposal.proposal_type == "new_outcome" do %>
                      <.text_input
                        id="outcome-proposal-title-input"
                        field={@outcome_proposal_form[:title]}
                        type="basic"
                        label={gettext("Title")}
                        required
                        show_required
                        show_suffix={false}
                      />
                      <div data-part="outcome-modal-select">
                        <.label label={gettext("Motion")} required />
                        <.select
                          id="outcome-proposal-motion-select"
                          name="outcome_proposal[motion]"
                          label={gettext("Select motion")}
                          value={select_value(@outcome_proposal_form[:motion].value)}
                        >
                          <:item value="evaluation" label={gettext("Evaluation")} />
                          <:item value="adoption" label={gettext("Adoption")} />
                          <:item value="expansion" label={gettext("Expansion")} />
                          <:item value="renewal" label={gettext("Renewal")} />
                          <:item value="recovery" label={gettext("Recovery")} />
                        </.select>
                      </div>
                      <.text_input
                        id="outcome-proposal-target-date-input"
                        field={@outcome_proposal_form[:target_date]}
                        type="basic"
                        input_type="date"
                        label={gettext("Target date")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="outcome-proposal-success-measure-input"
                        field={@outcome_proposal_form[:success_measure]}
                        type="basic"
                        label={gettext("Success measure")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="outcome-proposal-baseline-input"
                        field={@outcome_proposal_form[:baseline]}
                        type="basic"
                        label={gettext("Baseline")}
                        show_suffix={false}
                      />
                      <.text_input
                        id="outcome-proposal-target-input"
                        field={@outcome_proposal_form[:target]}
                        type="basic"
                        label={gettext("Target")}
                        show_suffix={false}
                      />
                      <div data-part="outcome-modal-grid-full">
                        <.text_area
                          id="outcome-proposal-description-input"
                          field={@outcome_proposal_form[:description]}
                          label={gettext("Why this matters")}
                          rows={4}
                          max_length={2000}
                        />
                      </div>
                    <% else %>
                      <div data-part="outcome-modal-select">
                        <.label label={gettext("Health")} required />
                        <.select
                          id="outcome-proposal-health-select"
                          name="outcome_proposal[health]"
                          label={gettext("Select health")}
                          value={select_value(@outcome_proposal_form[:health].value)}
                        >
                          <:item value="on_track" label={gettext("On track")} />
                          <:item value="at_risk" label={gettext("At risk")} />
                          <:item value="off_track" label={gettext("Off track")} />
                          <:item value="unknown" label={gettext("Unknown")} />
                        </.select>
                      </div>
                      <div data-part="outcome-modal-grid-full">
                        <.text_area
                          id="outcome-proposal-summary-input"
                          field={@outcome_proposal_form[:summary]}
                          label={gettext("Evidence-based review")}
                          rows={4}
                          max_length={3000}
                          required
                        />
                      </div>
                      <div data-part="outcome-modal-grid-full">
                        <.text_area
                          id="outcome-proposal-recommendation-input"
                          field={@outcome_proposal_form[:recommendation]}
                          label={gettext("Recommended next move")}
                          rows={3}
                          max_length={1500}
                        />
                      </div>
                    <% end %>
                  </div>
                </.form>

                <.form
                  id="outcome-proposal-rejection-form"
                  for={@outcome_proposal_decision_form}
                  phx-submit="reject_outcome_proposal"
                >
                  <.text_area
                    id="outcome-proposal-rejection-reason-input"
                    field={@outcome_proposal_decision_form[:reason]}
                    label={gettext("Reason for rejecting")}
                    hint={gettext("This feedback helps prevent the same suggestion from returning.")}
                    rows={2}
                    max_length={1000}
                    required
                  />
                </.form>
              </div>

              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      label={gettext("Cancel")}
                      variant="secondary"
                      size="small"
                      type="button"
                      phx-click="close_outcome_proposal_modal"
                    />
                  </:action>
                  <:action>
                    <.button
                      id="reject-outcome-proposal-button"
                      label={gettext("Reject")}
                      variant="destructive"
                      size="small"
                      type="submit"
                      form="outcome-proposal-rejection-form"
                    />
                  </:action>
                  <:action>
                    <.button
                      id="approve-outcome-proposal-button"
                      label={gettext("Approve")}
                      size="small"
                      type="submit"
                      form="outcome-proposal-form"
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </div>
        </:actions>
        <.card_section data-part="outcomes-section">
          <div
            :if={pending_outcome_proposals(@account) != []}
            id="account-outcome-proposals"
            data-part="outcome-proposals"
          >
            <div data-part="outcome-proposals-header">
              <div data-part="outcome-proposals-heading">
                <span data-part="outcome-proposals-title">{gettext("Suggestions for review")}</span>
                <span data-part="outcome-proposals-description">
                  {gettext("Atlas found customer evidence worth turning into an outcome or review.")}
                </span>
              </div>
              <.badge
                label={to_string(length(pending_outcome_proposals(@account)))}
                color="information"
                style="light-fill"
              />
            </div>
            <div data-part="outcome-proposals-list">
              <div
                :for={proposal <- pending_outcome_proposals(@account)}
                id={"outcome-proposal-#{proposal.id}"}
                data-part="outcome-proposal"
              >
                <div data-part="outcome-proposal-content">
                  <div data-part="outcome-proposal-heading">
                    <span data-part="outcome-proposal-title">
                      {outcome_proposal_subject(proposal)}
                    </span>
                    <.badge
                      label={outcome_proposal_type_label(proposal)}
                      color="information"
                      style="light-fill"
                    />
                    <span data-part="outcome-proposal-confidence">
                      {outcome_proposal_confidence(proposal)}
                    </span>
                  </div>
                  <p data-part="outcome-proposal-rationale">{proposal.rationale}</p>
                  <div data-part="outcome-proposal-preview">
                    {outcome_proposal_preview(proposal)}
                  </div>
                  <div data-part="outcome-proposal-evidence-count">
                    {ngettext(
                      "%{count} evidence item",
                      "%{count} evidence items",
                      length(outcome_proposal_evidence(proposal)),
                      count: length(outcome_proposal_evidence(proposal))
                    )}
                  </div>
                </div>
                <div data-part="outcome-proposal-actions">
                  <.button
                    id={"review-outcome-proposal-button-#{proposal.id}"}
                    label={gettext("Review")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="open_outcome_proposal_modal"
                    phx-value-id={proposal.id}
                  />
                </div>
              </div>
            </div>
          </div>

          <div
            :if={@outcome_proposals_processing}
            id="outcome-proposals-processing"
            data-part="outcome-proposals-processing"
            aria-live="polite"
          >
            <span data-part="outcome-proposals-spinner" aria-hidden="true"></span>
            <span>{gettext("Reviewing recent evidence…")}</span>
          </div>
          <div
            :if={@outcome_proposals_error}
            id="outcome-proposals-error"
            data-part="outcome-proposals-error"
            role="alert"
          >
            {@outcome_proposals_error}
          </div>
          <div
            :if={@account.outcomes != []}
            id="account-outcomes-list"
            data-part="outcomes-list"
          >
            <div
              :for={outcome <- @account.outcomes}
              id={"outcome-#{outcome.id}"}
              data-part="outcome"
              data-status={outcome.status}
              data-health={outcome.health}
            >
              <div data-part="outcome-content">
                <div data-part="outcome-heading">
                  <span data-part="outcome-title">{outcome.title}</span>
                  <.badge
                    id={"outcome-health-#{outcome.id}"}
                    label={outcome_health_label(outcome.health)}
                    color={outcome_health_color(outcome.health)}
                    style="light-fill"
                  />
                  <.badge
                    id={"outcome-motion-#{outcome.id}"}
                    label={outcome_motion_label(outcome.motion)}
                    color="neutral"
                    style="light-fill"
                  />
                  <.badge
                    :if={outcome.status != "active"}
                    id={"outcome-status-#{outcome.id}"}
                    label={outcome_status_label(outcome.status)}
                    color="neutral"
                    style="light-fill"
                  />
                </div>
                <p :if={outcome.description} data-part="outcome-description">
                  {outcome.description}
                </p>
                <div :if={outcome.success_measure} data-part="outcome-measure">
                  <span data-part="outcome-meta-label">{gettext("Success")}</span>
                  <span>{outcome.success_measure}</span>
                </div>
                <div :if={outcome.baseline || outcome.target} data-part="outcome-progress">
                  <span>{outcome.baseline || gettext("Unknown baseline")}</span>
                  <.icon name="arrow_right" />
                  <span>{outcome.target || gettext("Target not set")}</span>
                </div>
                <div :if={outcome.target_date} data-part="outcome-target-date">
                  {gettext("Target %{date}", date: format_date(outcome.target_date))}
                </div>
                <div :if={latest_outcome_review(outcome)} data-part="outcome-latest-review">
                  <div data-part="outcome-review-header">
                    <span data-part="outcome-meta-label">{gettext("Latest review")}</span>
                    <.time time={latest_outcome_review(outcome).reviewed_at} />
                  </div>
                  <p>{latest_outcome_review(outcome).summary}</p>
                  <div
                    :if={latest_outcome_review(outcome).recommendation}
                    data-part="outcome-recommendation"
                  >
                    <span data-part="outcome-meta-label">{gettext("Recommended next move")}</span>
                    <p>{latest_outcome_review(outcome).recommendation}</p>
                  </div>
                </div>
              </div>
              <div :if={outcome.status == "active"} data-part="outcome-actions">
                <.button
                  id={"review-outcome-button-#{outcome.id}"}
                  label={gettext("Review")}
                  variant="secondary"
                  size="small"
                  type="button"
                  phx-click="open_outcome_review_modal"
                  phx-value-id={outcome.id}
                />
                <.button
                  id={"achieve-outcome-button-#{outcome.id}"}
                  label={gettext("Mark Achieved")}
                  variant="secondary"
                  size="small"
                  type="button"
                  phx-click="achieve_outcome"
                  phx-value-id={outcome.id}
                />
              </div>
            </div>
          </div>

          <.account_empty_state
            :if={@account.outcomes == []}
            title={gettext("No customer outcomes yet")}
            subtitle={
              gettext(
                "Define the result this account is trying to achieve, how success is measured, and when it matters."
              )
            }
          />
        </.card_section>
      </.card>

      <.card title={gettext("Timeline")} icon="timeline_event" data-part="timeline-card">
        <:actions>
          <.button
            :if={@account.events != []}
            id="record-feature-interest-button"
            label={gettext("Record feature interest")}
            variant="secondary"
            size="small"
            type="button"
            phx-click="open_feature_interest_modal"
          />
        </:actions>
        <.card_section data-part="timeline-section">
          <.form
            id="timeline-note-form"
            for={@note_form}
            phx-submit="add_note"
            phx-hook="ScreenshotPaste"
            data-part="timeline-note-form"
          >
            <.text_area
              id="timeline-note-input"
              data-part="timeline-note-input"
              field={@note_form[:body]}
              label={gettext("Add a note")}
              placeholder={
                gettext(
                  "Share what happened, follow-ups, or context Atlas should remember. Or paste a screenshot."
                )
              }
              rows={3}
              max_length={2000}
            />
            <div
              :if={@staged_screenshots != []}
              id="timeline-screenshot-tray"
              data-part="timeline-screenshot-tray"
              aria-label={gettext("Staged screenshots")}
            >
              <div data-part="timeline-screenshot-tray-header">
                <span data-part="timeline-screenshot-count">
                  {Screenshots.count_label(length(@staged_screenshots))}
                </span>
                <button
                  id="timeline-screenshot-clear"
                  data-part="timeline-screenshot-clear"
                  type="button"
                  phx-click="clear_staged_screenshots"
                  disabled={@screenshot_processing}
                >
                  {gettext("Clear")}
                </button>
              </div>
              <div data-part="timeline-screenshot-list">
                <div
                  :for={screenshot <- @staged_screenshots}
                  id={"staged-#{screenshot.id}"}
                  data-part="timeline-screenshot"
                >
                  <img
                    data-part="timeline-screenshot-preview"
                    src={Screenshots.preview_src(screenshot)}
                    alt={gettext("Pasted screenshot")}
                  />
                  <button
                    id={"remove-#{screenshot.id}"}
                    data-part="timeline-screenshot-remove"
                    type="button"
                    phx-click="remove_staged_screenshot"
                    phx-value-id={screenshot.id}
                    aria-label={gettext("Remove screenshot")}
                    disabled={@screenshot_processing}
                  >
                    <.icon name="close" />
                  </button>
                </div>
              </div>
            </div>
            <div
              :if={@screenshot_processing}
              id="timeline-note-processing"
              data-part="timeline-note-processing"
              aria-live="polite"
            >
              <span data-part="timeline-note-spinner" aria-hidden="true"></span>
              <span>
                {Screenshots.analysis_label(length(@staged_screenshots))}
              </span>
            </div>
            <div
              :if={@screenshot_error}
              id="timeline-note-error"
              data-part="timeline-note-error"
              role="alert"
            >
              {@screenshot_error}
            </div>
            <div data-part="timeline-note-actions">
              <.button
                :if={@screenshot_error && @staged_screenshots != []}
                id="timeline-screenshot-retry"
                label={gettext("Try screenshot again")}
                variant="secondary"
                size="small"
                type="button"
                phx-click="draft_from_screenshots"
                disabled={@screenshot_processing}
              >
                <:icon_left><.icon name="photo" /></:icon_left>
              </.button>
              <.button
                id="timeline-note-submit"
                label={gettext("Add Note")}
                size="small"
                type="submit"
                disabled={@screenshot_processing}
              />
            </div>
          </.form>

          <div data-part="timeline">
            <%= for event <- @account.events do %>
              <%= cond do %>
                <% event.kind == "slack_message" -> %>
                  <.slack_timeline_event
                    event={event}
                    replies={Map.get(@slack_threads, event.id, [])}
                  />
                <% true -> %>
                  <div id={"timeline-event-#{event.id}"} data-part="timeline-event">
                    <div data-part="timeline-event-icon">
                      <.icon name={event_icon(event)} />
                    </div>
                    <div data-part="timeline-event-content">
                      <div data-part="timeline-event-header">
                        <span data-part="timeline-event-title">{event_title(event)}</span>
                        <span
                          :if={event_author_name(event)}
                          data-part="timeline-event-author"
                        >
                          {event_author_name(event)}
                        </span>
                        <span data-part="timeline-event-time">
                          {format_datetime(event.occurred_at)}
                        </span>
                      </div>
                      <div :if={event_card_body(event)} data-part="timeline-event-body">
                        {event_card_body_html(event)}
                      </div>
                      <a
                        :if={event.url}
                        data-part="timeline-event-link"
                        href={event.url}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        {gettext("Open reference")}
                      </a>
                    </div>
                  </div>
              <% end %>
            <% end %>

            <.account_empty_state
              :if={@account.events == []}
              title={gettext("No timeline events yet")}
              subtitle={gettext("Add a note above or insert timeline events to show them here.")}
            />
          </div>
        </.card_section>
      </.card>

      <.modal
        :if={@feature_interest_modal_open?}
        id="feature-interest-modal"
        title={gettext("Record feature interest")}
        description={gettext("Choose the timeline event that provides evidence for this request.")}
        header_type="icon"
        header_size="small"
        on_dismiss="close_feature_interest_modal"
      >
        <:header_icon><.message_circle /></:header_icon>
        <:trigger :let={modal_attrs}>
          <button id="feature-interest-modal-trigger" type="button" hidden {modal_attrs}></button>
        </:trigger>
        <div data-part="feature-interest-modal-content">
          <.form
            id="feature-interest-form"
            for={@feature_interest_form}
            phx-submit="record_feature_interest"
          >
            <div data-part="feature-interest-modal-select">
              <.label label={gettext("Source event")} required />
              <.select
                id="feature-interest-event-select"
                name="feature_interest[account_event_id]"
                label={gettext("Choose a timeline event")}
                value={select_value(@feature_interest_form[:account_event_id].value)}
              >
                <:item
                  :for={event <- @account.events}
                  value={event.id}
                  label={feature_interest_event_option_label(event)}
                />
              </.select>
            </div>
            <.text_input
              id="feature-interest-title-input"
              field={@feature_interest_form[:title]}
              type="basic"
              label={gettext("Capability")}
              placeholder={gettext("Remote build runners")}
              required
              show_required
              show_suffix={false}
            />
            <.text_area
              id="feature-interest-summary-input"
              field={@feature_interest_form[:summary]}
              label={gettext("What the account needs")}
              placeholder={gettext("Summarize the request and why it matters to this account.")}
              rows={4}
              max_length={2000}
              required
            />
            <.text_area
              id="feature-interest-notes-input"
              field={@feature_interest_form[:notes]}
              label={gettext("Account context")}
              hint={gettext("Optional context, such as the current solution or pain points.")}
              rows={3}
              max_length={2000}
            />
          </.form>
        </div>
        <:footer>
          <.modal_footer>
            <:action>
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="small"
                type="button"
                phx-click="close_feature_interest_modal"
              />
            </:action>
            <:action>
              <.button
                id="record-feature-interest-submit"
                label={gettext("Record interest")}
                size="small"
                type="submit"
                form="feature-interest-form"
              />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>

      <.modal
        :if={@selected_feature_interest_account}
        id="feature-interest-notes-modal"
        title={gettext("Edit account context")}
        description={
          gettext("Keep the current solution, pain points, and other context alongside this request.")
        }
        header_type="icon"
        header_size="small"
        on_dismiss="close_feature_interest_notes_modal"
      >
        <:header_icon><.message_circle /></:header_icon>
        <:trigger :let={modal_attrs}>
          <button id="feature-interest-notes-modal-trigger" type="button" hidden {modal_attrs}>
          </button>
        </:trigger>
        <div data-part="feature-interest-modal-content">
          <.form
            id="feature-interest-notes-form"
            for={@feature_interest_notes_form}
            phx-submit="save_feature_interest_notes"
          >
            <.text_area
              id="feature-interest-notes-edit-input"
              field={@feature_interest_notes_form[:notes]}
              label={gettext("Account context")}
              hint={
                gettext(
                  "For example, record the current solution, pain points, or decision criteria."
                )
              }
              rows={5}
              max_length={2000}
            />
          </.form>
        </div>
        <:footer>
          <.modal_footer>
            <:action>
              <.button
                label={gettext("Cancel")}
                variant="secondary"
                size="small"
                type="button"
                phx-click="close_feature_interest_notes_modal"
              />
            </:action>
            <:action>
              <.button
                id="save-feature-interest-notes-submit"
                label={gettext("Save context")}
                size="small"
                type="submit"
                form="feature-interest-notes-form"
              />
            </:action>
          </.modal_footer>
        </:footer>
      </.modal>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp metadata_item(assigns) do
    ~H"""
    <div data-part="metadata">
      <div data-part="metadata-title">{@title}</div>
      <div data-part="metadata-value">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :rest, :global

  defp account_empty_state(assigns) do
    ~H"""
    <div id={@id} data-part="empty-state" {@rest}>
      <div data-part="empty-background" aria-hidden="true"></div>
      <div data-part="empty-image" aria-hidden="true">
        <img src={~p"/images/empty_table_light.png"} data-theme="light" alt="" />
        <img src={~p"/images/empty_table_dark.png"} data-theme="dark" alt="" />
      </div>
      <div data-part="empty-content">
        <span data-part="empty-title">{@title}</span>
        <span :if={@subtitle} data-part="empty-subtitle">{@subtitle}</span>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true
  attr :replies, :list, default: []

  defp slack_timeline_event(assigns) do
    assigns =
      assign(
        assigns,
        :slack_mention_labels,
        slack_mention_labels(assigns.event, assigns.replies)
      )

    ~H"""
    <div
      id={"timeline-event-#{@event.id}"}
      data-part="timeline-event"
      data-variant="slack"
    >
      <div data-part="timeline-event-icon">
        <.icon name="brand_slack" />
      </div>
      <div data-part="timeline-event-content">
        <div data-part="slack-message">
          <div data-part="slack-message-header">
            <.avatar
              id={"slack-event-avatar-#{@event.id}"}
              size="2xsmall"
              name={slack_event_author(@event)}
              image_href={slack_event_author_avatar(@event)}
            />
            <div data-part="slack-message-author-meta">
              <span data-part="slack-message-author-name">
                {slack_event_author(@event)}
              </span>
              <span
                :if={slack_event_external?(@event)}
                data-part="slack-message-customer-tag"
              >
                {gettext("Customer")}
              </span>
            </div>
            <span data-part="slack-channel-tag">
              {slack_event_channel(@event)}
            </span>
            <span data-part="timeline-event-time">
              {format_datetime(@event.occurred_at)}
            </span>
          </div>
          <div :if={@event.body && @event.body != ""} data-part="slack-message-body">
            {slack_message_html(@event.body, @slack_mention_labels)}
          </div>
          <a
            :if={@event.url}
            data-part="slack-message-link"
            href={@event.url}
            target="_blank"
            rel="noopener noreferrer"
          >
            {gettext("Open in Slack")}
          </a>
        </div>

        <div :if={@replies != []} data-part="slack-thread-replies">
          <div
            :for={reply <- @replies}
            id={"slack-thread-reply-#{reply.id}"}
            data-part="slack-thread-reply"
          >
            <.avatar
              id={"slack-thread-reply-avatar-#{reply.id}"}
              size="2xsmall"
              name={slack_reply_author(reply)}
              image_href={slack_reply_avatar(reply)}
            />
            <div data-part="slack-thread-reply-content">
              <div data-part="slack-thread-reply-header">
                <span data-part="slack-thread-reply-author">
                  {slack_reply_author(reply)}
                </span>
                <span
                  :if={slack_reply_external?(reply)}
                  data-part="slack-message-customer-tag"
                >
                  {gettext("Customer")}
                </span>
                <%= if reply.permalink do %>
                  <a
                    data-part="timeline-event-time"
                    href={reply.permalink}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {format_datetime(reply.posted_at)}
                  </a>
                <% else %>
                  <span data-part="timeline-event-time">
                    {format_datetime(reply.posted_at)}
                  </span>
                <% end %>
              </div>
              <div :if={reply.text && reply.text != ""} data-part="slack-thread-reply-body">
                {slack_message_html(reply.text, @slack_mention_labels)}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp assign_account(socket, account) do
    linked_channels = Slack.list_channels_for_account(account)
    linked_slack_channel = List.first(linked_channels)
    slack_channel_options = Slack.list_available_channels()

    socket
    |> InvoicesView.maybe_refresh(account)
    |> assign(:account, account)
    |> assign(:ready_to_sign_tax_certificate_requests, ready_to_sign_tax_certificate_requests(account))
    |> assign(:feature_interests, Accounts.list_feature_interests_for_account(account))
    |> assign(:pocs, POCs.list_pocs(account_id: account.id))
    |> assign(:nudges, Nudges.list_nudges(account, limit: 20))
    |> clear_feature_interest_modal()
    |> clear_feature_interest_notes_modal()
    |> assign(:linked_slack_channel, linked_slack_channel)
    |> assign(:slack_channel_options, slack_channel_options)
    |> assign_selected_slack_channel(selected_slack_channel_value(linked_slack_channel), slack_channel_options)
    |> assign(:parent_account_options, Accounts.list_parent_account_options(account.id))
    |> assign(:slack_threads, slack_threads_for(account))
    |> assign_account_form(account)
    |> assign_handle_form(account)
    |> assign_contact_modal(:create, nil)
    |> assign_term_modal(:create, nil)
    |> assign_outcome_modal()
    |> assign(:selected_outcome, nil)
    |> assign(:outcome_review_form, nil)
    |> clear_outcome_proposal_modal()
    |> assign_note_form(account)
    |> assign(:leadership?, Users.has_scope?(socket.assigns.current_user, "briefs:read"))
    |> assign_tax_certificate_request_form(account)
    |> assign(:signed_tax_certificate_upload_form, to_form(%{}, as: "signed_tax_certificate"))
  end

  defp evaluation_status_color("active"), do: "information"
  defp evaluation_status_color("closed_won"), do: "success"
  defp evaluation_status_color("closed_lost"), do: "destructive"
  defp evaluation_status_color(_status), do: "neutral"

  defp slack_threads_for(account) do
    account.events
    |> Enum.filter(&(&1.kind == "slack_message"))
    |> Enum.map(& &1.id)
    |> Slack.thread_replies_by_account_event()
  end

  defp account_feature_interest(interest), do: List.first(interest.accounts)
  defp account_feature_interest_summary(interest), do: account_feature_interest(interest).summary
  defp account_feature_interest_notes(interest), do: account_feature_interest(interest).notes
  defp account_feature_interest_event(interest), do: account_feature_interest(interest).account_event
  defp account_feature_interest_thread(interest), do: account_feature_interest(interest).support_thread

  defp find_feature_interest_account(interests, id) do
    interests
    |> Enum.map(&account_feature_interest/1)
    |> Enum.find(&(&1.id == id))
  end

  defp assign_term_modal(socket, mode, term) do
    changeset =
      case {mode, term} do
        {:edit, term} when not is_nil(term) -> Accounts.change_term(term)
        _ -> Accounts.change_term(socket.assigns.account)
      end

    socket
    |> assign(:term_modal_mode, mode)
    |> assign(:selected_term, term)
    |> assign(:term_form, to_form(changeset, as: "term"))
  end

  defp assign_note_form(socket, account, body \\ nil) do
    attrs = if is_binary(body) and body != "", do: %{"body" => body}, else: %{}
    assign(socket, :note_form, to_form(Accounts.change_note(account, attrs), as: "note"))
  end

  defp assign_tax_certificate_request_form(socket, account) do
    assign(
      socket,
      :tax_certificate_form,
      to_form(Letters.change_tax_certificate_request(account), as: "tax_certificate")
    )
  end

  defp ready_to_sign_tax_certificate_requests(account) do
    account
    |> Letters.list_account_letters()
    |> Enum.filter(&(&1.status == "awaiting_signature" and not is_nil(&1.document)))
  end

  defp signed_tax_certificate_upload_modal_id(letter_id), do: "signed-tax-certificate-request-upload-modal-#{letter_id}"

  defp assign_feature_interest_modal(socket) do
    socket
    |> assign(:feature_interest_modal_open?, true)
    |> assign(:feature_interest_form, to_form(Accounts.change_feature_interest(), as: "feature_interest"))
  end

  defp clear_feature_interest_modal(socket) do
    socket
    |> assign(:feature_interest_modal_open?, false)
    |> assign(:feature_interest_form, to_form(Accounts.change_feature_interest(), as: "feature_interest"))
  end

  defp feature_interest_event_option_label(event) do
    "#{event_title(event)} · #{format_datetime(event.occurred_at)}"
  end

  defp assign_feature_interest_notes_modal(socket, interest_account) do
    socket
    |> assign(:selected_feature_interest_account, interest_account)
    |> assign(
      :feature_interest_notes_form,
      to_form(Accounts.change_feature_interest_notes(interest_account), as: "feature_interest_notes")
    )
  end

  defp clear_feature_interest_notes_modal(socket) do
    socket
    |> assign(:selected_feature_interest_account, nil)
    |> assign(:feature_interest_notes_form, nil)
  end

  defp assign_account_form(socket, account) do
    assign(socket, :account_form, to_form(Accounts.change_account(account), as: "account"))
  end

  defp contract_value_label(account) do
    {value, currency} = Accounts.contract_value(account)
    Amounts.format(value, currency)
  end

  defp parent_account_option_label(%{name: name, primary_domain: domain}) when is_binary(domain) and domain != "" do
    "#{name} (#{domain})"
  end

  defp parent_account_option_label(%{name: name}), do: name

  defp normalize_slack_channel_value(value) when value in [nil, "", "_none"], do: nil
  defp normalize_slack_channel_value(value), do: value

  defp assign_selected_slack_channel(socket, value, options \\ nil) do
    options = options || socket.assigns.slack_channel_options

    assign(socket,
      selected_slack_channel_value: value,
      selected_slack_channel_label: slack_channel_dropdown_label(value, options)
    )
  end

  defp assign_handle_form(socket, account) do
    assign(socket, :handle_form, to_form(Accounts.change_account_handle(account), as: "account_handle"))
  end

  defp assign_contact_modal(socket, mode, contact) do
    form =
      case {mode, contact} do
        {:edit, contact} when not is_nil(contact) -> Accounts.change_contact(contact)
        _ -> Accounts.change_contact(socket.assigns.account)
      end

    socket
    |> assign(:contact_modal_mode, mode)
    |> assign(:selected_contact, contact)
    |> assign(:contact_form, to_form(form, as: "contact"))
  end

  defp assign_outcome_modal(socket) do
    changeset = Accounts.change_outcome(socket.assigns.account)
    assign(socket, :outcome_form, to_form(changeset, as: "outcome"))
  end

  defp assign_outcome_proposal_modal(socket, proposal) do
    socket
    |> assign(:selected_outcome_proposal, proposal)
    |> assign(
      :outcome_proposal_form,
      to_form(Accounts.change_outcome_proposal(proposal), as: "outcome_proposal")
    )
    |> assign(
      :outcome_proposal_decision_form,
      to_form(%{"reason" => ""}, as: "proposal_decision")
    )
  end

  defp clear_outcome_proposal_modal(socket) do
    socket
    |> assign(:selected_outcome_proposal, nil)
    |> assign(:outcome_proposal_form, nil)
    |> assign(:outcome_proposal_decision_form, nil)
  end

  defp assign_outcome_review_modal(socket, outcome) do
    changeset = Accounts.change_outcome_review(outcome, %{"health" => outcome.health})

    socket
    |> assign(:selected_outcome, outcome)
    |> assign(:outcome_review_form, to_form(changeset, as: "outcome_review"))
  end

  defp find_outcome(%{outcomes: outcomes}, id) when is_list(outcomes) do
    target_id = to_string(id)
    Enum.find(outcomes, &(to_string(&1.id) == target_id))
  end

  defp find_outcome(_account, _id), do: nil

  defp latest_outcome_review(%{reviews: [review | _reviews]}), do: review
  defp latest_outcome_review(_outcome), do: nil

  defp pending_outcome_proposals(%{outcome_proposals: proposals}) when is_list(proposals) do
    Enum.filter(proposals, &(&1.status == "pending"))
  end

  defp pending_outcome_proposals(_account), do: []

  defp refresh_nudges(socket, message) do
    account = socket.assigns.account

    socket
    |> assign(:nudges, Nudges.list_nudges(account, limit: 20))
    |> put_flash(:info, message)
  end

  defp handle_send_result({:ok, %{duplicate: true}}, socket),
    do: {:noreply, refresh_nudges(socket, gettext("Email already queued in the last 15 minutes."))}

  defp handle_send_result({:ok, _nudge}, socket), do: {:noreply, refresh_nudges(socket, gettext("Email queued."))}

  defp handle_send_result({:error, reason}, socket),
    do: {:noreply, put_flash(socket, :error, send_error_message(reason))}

  defp send_error_message(:not_found), do: gettext("Nudge not found.")

  defp send_error_message(:not_authorized),
    do: gettext("You must be the claimant or hold admin:write to send this nudge.")

  defp send_error_message({:invalid_state, state}),
    do: gettext("Nudge is in state %{s}; only claimed nudges can be sent.", s: state)

  defp send_error_message(:contact_missing), do: gettext("This nudge has no contact. Add or edit a contact first.")

  defp send_error_message(:contact_email_missing), do: gettext("The nudge's contact has no email address.")

  defp send_error_message(:contact_bounced), do: gettext("The nudge's contact is marked as bounced.")

  defp send_error_message(:contact_opted_out), do: gettext("The nudge's contact has opted out of outreach.")

  defp send_error_message(_reason), do: gettext("Could not send the nudge.")

  defp nudge_stage(nudge), do: Nudges.stage_for(nudge)

  defp nudge_state_label(%{state: "pending_post"}, _stage), do: gettext("Posting to Slack…")
  defp nudge_state_label(%{state: "proposed"}, _stage), do: gettext("Open")
  defp nudge_state_label(%{state: "claimed"}, _stage), do: gettext("Claimed")
  defp nudge_state_label(%{state: "sent"}, :delivered), do: gettext("Sent")
  defp nudge_state_label(%{state: "sent"}, :failed), do: gettext("Send failed")
  defp nudge_state_label(%{state: "sent"}, :retrying), do: gettext("Sent (retrying)")
  defp nudge_state_label(%{state: "sent"}, _stage), do: gettext("Sent (queued)")
  defp nudge_state_label(%{state: "dismissed"}, _stage), do: gettext("Dismissed")
  defp nudge_state_label(%{state: "expired"}, _stage), do: gettext("Expired")
  defp nudge_state_label(%{state: state}, _stage), do: state

  defp nudge_state_color(%{state: "pending_post"}, _stage), do: "neutral"
  defp nudge_state_color(%{state: "proposed"}, _stage), do: "information"
  defp nudge_state_color(%{state: "claimed"}, _stage), do: "success"
  defp nudge_state_color(%{state: "sent"}, :delivered), do: "success"
  defp nudge_state_color(%{state: "sent"}, :failed), do: "destructive"
  defp nudge_state_color(%{state: "sent"}, _stage), do: "attention"
  defp nudge_state_color(%{state: "dismissed"}, _stage), do: "neutral"
  defp nudge_state_color(%{state: "expired"}, _stage), do: "neutral"
  defp nudge_state_color(_nudge, _stage), do: "neutral"

  defp format_nudge_timestamp(nil), do: "-"
  defp format_nudge_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_nudge_timestamp(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y")

  defp outcome_proposal_subject(%OutcomeProposal{proposal_type: "new_outcome", title: title}), do: title

  defp outcome_proposal_subject(%OutcomeProposal{outcome: %Outcome{title: title}}) do
    gettext("Review %{title}", title: title)
  end

  defp outcome_proposal_subject(_proposal), do: gettext("Outcome review")

  defp outcome_proposal_type_label(%OutcomeProposal{proposal_type: "new_outcome"}), do: gettext("New outcome")

  defp outcome_proposal_type_label(_proposal), do: gettext("Outcome review")

  defp outcome_proposal_preview(%OutcomeProposal{proposal_type: "new_outcome"} = proposal) do
    [proposal.success_measure, proposal.target && gettext("Target: %{target}", target: proposal.target)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp outcome_proposal_preview(%OutcomeProposal{summary: summary}), do: summary

  defp outcome_proposal_evidence(%OutcomeProposal{evidence: %{"items" => items}}) when is_list(items), do: items
  defp outcome_proposal_evidence(_proposal), do: []

  defp outcome_proposal_evidence_observation(item) when is_map(item) do
    Map.get(item, "observation") || Map.get(item, :observation)
  end

  defp outcome_proposal_evidence_observation(_item), do: nil

  defp outcome_proposal_confidence(%OutcomeProposal{confidence: %Decimal{} = confidence}) do
    percentage = confidence |> Decimal.mult(100) |> Decimal.round(0) |> Decimal.to_integer()
    gettext("%{percentage}%", percentage: percentage)
  end

  defp outcome_proposal_confidence(_proposal), do: gettext("Unknown confidence")

  defp outcome_health_label("on_track"), do: gettext("On track")
  defp outcome_health_label("at_risk"), do: gettext("At risk")
  defp outcome_health_label("off_track"), do: gettext("Off track")
  defp outcome_health_label(_health), do: gettext("Unknown")

  defp outcome_health_color("on_track"), do: "success"
  defp outcome_health_color("at_risk"), do: "warning"
  defp outcome_health_color("off_track"), do: "destructive"
  defp outcome_health_color(_health), do: "neutral"

  defp outcome_motion_label(motion), do: motion |> to_string() |> String.replace("_", " ") |> String.capitalize()
  defp outcome_status_label(status), do: status |> to_string() |> String.replace("_", " ") |> String.capitalize()

  # `:configuration` features (see `Atlas.FeatureUsage.Catalog`) measure a state
  # the account has set up rather than a stream of events, so the widget reads
  # "3 / enabled in their projects" instead of "3 / events in the last 7 days".
  defp feature_value_caption(:configuration, :account), do: gettext("configured for this account")
  defp feature_value_caption(:configuration, _scope), do: gettext("enabled in their projects")
  defp feature_value_caption(_kind, _scope), do: gettext("events in the last 7 days")

  defp feature_breakdown_caption(:configuration), do: gettext("configured in total")
  defp feature_breakdown_caption(_kind), do: gettext("in last 24h")

  defp feature_last_changed_label(:configuration), do: gettext("Last changed")
  defp feature_last_changed_label(_kind), do: gettext("Last used")

  defp account_document_meta(document) do
    [
      document.document_type && AtlasWeb.DocumentsLive.humanize(document.document_type.name),
      document.correspondent && document.correspondent.name,
      format_date(document.document_date)
    ]
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join(" / ")
    |> case do
      "" -> gettext("Document")
      meta -> meta
    end
  end

  defp service_level_category_label(nil), do: gettext("Other")

  defp service_level_category_label(category) do
    AtlasWeb.DocumentsLive.humanize(category)
  end

  defp service_level_window(%{applies_from: %Date{} = from, applies_until: %Date{} = until}) do
    gettext("%{from} to %{until}", from: format_date(from), until: format_date(until))
  end

  defp service_level_window(%{applies_from: %Date{} = from}) do
    gettext("From %{from}", from: format_date(from))
  end

  defp service_level_window(%{applies_until: %Date{} = until}) do
    gettext("Until %{until}", until: format_date(until))
  end

  defp service_level_window(_service_level), do: nil

  defp service_level_document_title(%{document: %{title: title}}) when is_binary(title) and title != "" do
    title
  end

  defp service_level_document_title(_service_level), do: gettext("Source document")

  defp start_screenshot_analysis(socket) do
    staged_screenshots = socket.assigns.staged_screenshots

    cond do
      socket.assigns.screenshot_processing ->
        socket

      staged_screenshots == [] ->
        socket

      true ->
        account = socket.assigns.account
        min_ms = @screenshot_min_processing_ms

        socket
        |> assign(:screenshot_processing, true)
        |> assign(:screenshot_error, nil)
        |> start_async(:screenshot_analysis, fn ->
          started_at = System.monotonic_time(:millisecond)

          screenshots =
            Enum.map(staged_screenshots, fn screenshot ->
              %{data: screenshot.data, media_type: screenshot.media_type}
            end)

          result =
            screenshot_note_agent().draft_note_from_screenshots(screenshots, %{
              id: account.id,
              name: account.name
            })

          elapsed = System.monotonic_time(:millisecond) - started_at
          if elapsed < min_ms, do: Process.sleep(min_ms - elapsed)
          result
        end)
    end
  end

  defp screenshot_note_agent do
    :atlas
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:screenshot_note_agent, ScreenshotNoteAgent)
  end

  defp find_contact(account, id) do
    target_id = to_string(id)

    Enum.find(account.contacts, &(to_string(&1.id) == target_id))
  end
end
