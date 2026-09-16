defmodule Atlas.Finance.Financings do
  @moduledoc """
  Context for hardware financing arrangements.

  Every mutation reloads the parent `Financing` under `SELECT ... FOR UPDATE`
  inside a transaction, applies changes, and records an audit entry after
  the transaction commits. Line-set replacement and payment operations lock
  the parent row per Codex's round-3 note that PostgreSQL `FOR UPDATE` only
  locks retrieved rows; locking existing children does not prevent
  concurrent inserts.

  Design in `docs/hardware-financing-and-attribution-proposal.md`.
  """

  import Ecto.Query

  alias Atlas.Assets
  alias Atlas.Assets.Asset
  alias Atlas.Audit
  alias Atlas.Documents.Document
  alias Atlas.Finance.Financing
  alias Atlas.Finance.FinancingDocument
  alias Atlas.Finance.FinancingLine
  alias Atlas.Finance.FinancingPayment
  alias Atlas.Finance.FinancingSchedule
  alias Atlas.Finance.Transaction
  alias Atlas.Repo

  @dashboard_prefix "/operations/hardware/financings"
  @accepted_document_statuses ~w(uploaded processing ready)

  ## ------------------------------------------------------------------
  ## Reads
  ## ------------------------------------------------------------------

  def get(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> Financing |> Repo.get(id) |> preload_financing()
      :error -> nil
    end
  end

  def get(_id), do: nil

  def get!(id) when is_binary(id) do
    Financing
    |> Repo.get!(id)
    |> preload_financing()
  end

  def list(params \\ %{}, opts \\ []) do
    Financing
    |> maybe_filter_query(Keyword.get(opts, :query))
    |> order_by([f], desc: f.disbursement_or_commencement_on, asc: f.id)
    |> preload([:lines, documents: :document])
    |> Flop.run(struct(Flop, params), for: Financing)
  end

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    pattern = "%#{String.replace(value, "%", "\\%")}%"

    where(
      query,
      [financing],
      ilike(financing.provider, ^pattern) or ilike(financing.supplier, ^pattern) or
        ilike(financing.reference, ^pattern)
    )
  end

  def list_schedules(%Financing{id: id}, params \\ %{}) do
    FinancingSchedule
    |> where([s], s.financing_id == ^id)
    |> order_by([s], asc: s.sequence, asc: s.id)
    |> Flop.run(struct(Flop, params), for: FinancingSchedule)
  end

  def list_lines(%Financing{id: id}) do
    FinancingLine
    |> where([l], l.financing_id == ^id)
    |> preload([:asset])
    |> Repo.all()
  end

  def list_payments(%Financing{id: id}, params \\ %{}) do
    FinancingPayment
    |> where([p], p.financing_id == ^id)
    |> order_by([p], desc: p.paid_on, desc: p.id)
    |> preload([:schedule])
    |> Flop.run(struct(Flop, params), for: FinancingPayment)
  end

  def list_asset_financings(asset_id) when is_binary(asset_id) do
    FinancingLine
    |> where([l], l.asset_id == ^asset_id)
    |> preload([:financing])
    |> Repo.all()
  end

  def list_documents(%Financing{id: id}) do
    FinancingDocument
    |> where([link], link.financing_id == ^id)
    |> preload(:document)
    |> order_by([link],
      asc:
        fragment(
          "array_position(ARRAY['supplier_contract','financing_agreement','guarantee','invoice','acceptance','schedule','amendment','other']::text[], ?)",
          link.kind
        ),
      desc: link.inserted_at
    )
    |> Repo.all()
  end

  def get_payment(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> FinancingPayment |> Repo.get(id) |> Repo.preload([:financing, :schedule])
      :error -> nil
    end
  end

  ## ------------------------------------------------------------------
  ## Mutations
  ## ------------------------------------------------------------------

  def change_financing(attrs \\ %{}), do: Financing.create_changeset(%Financing{}, attrs)

  def create(attrs) when is_map(attrs) do
    %Financing{}
    |> Financing.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, financing} ->
        audit("financing.created", financing, %{
          "type" => financing.type,
          "provider" => financing.provider,
          "currency" => financing.currency
        })

        {:ok, preload_financing(financing)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def edit_metadata(%Financing{} = financing, attrs) do
    with_locked(financing, fn current ->
      current
      |> Financing.metadata_changeset(attrs)
      |> Repo.update()
    end)
    |> after_lifecycle("financing.metadata_edited", %{
      "changed_fields" => attrs |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    })
  end

  def attach_document(%Financing{} = financing, document_id, kind, opts \\ []) when is_binary(document_id) do
    case Repo.get(Document, document_id) do
      %Document{status: status} when status in @accepted_document_statuses ->
        %FinancingDocument{}
        |> FinancingDocument.create_changeset(%{
          financing_id: financing.id,
          document_id: document_id,
          kind: to_string(kind),
          notes: Keyword.get(opts, :notes)
        })
        |> Repo.insert()
        |> case do
          {:ok, link} = ok ->
            audit("financing.document_attached", financing, %{
              "document_id" => document_id,
              "kind" => link.kind
            })

            ok

          other ->
            other
        end

      %Document{} ->
        {:error, :document_not_ready}

      nil ->
        {:error, :document_not_found}
    end
  end

  def detach_document(link_id) when is_binary(link_id) do
    case Repo.get(FinancingDocument, link_id) do
      nil ->
        {:error, :not_found}

      link ->
        financing = Repo.get!(Financing, link.financing_id)

        case Repo.delete(link) do
          {:ok, deleted} = ok ->
            audit("financing.document_detached", financing, %{
              "document_id" => deleted.document_id,
              "kind" => deleted.kind
            })

            ok

          other ->
            other
        end
    end
  end

  def set_accounting_treatment(%Financing{} = financing, treatment, evidence) do
    with_locked(financing, fn current ->
      previous = %{
        treatment: current.accounting_treatment,
        evidence: current.treatment_evidence
      }

      current
      |> Financing.treatment_changeset(%{
        accounting_treatment: treatment,
        treatment_evidence: evidence
      })
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, {updated, previous}}
        {:error, changeset} -> {:error, changeset}
      end
    end)
    |> case do
      {:ok, {updated, previous}} ->
        audit("financing.treatment_set", updated, %{
          "previous_treatment" => previous.treatment,
          "previous_evidence" => previous.evidence,
          "new_treatment" => updated.accounting_treatment,
          "new_evidence" => updated.treatment_evidence
        })

        {:ok, preload_financing(updated)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Atomic replacement of the line set for a financing.

  Requires the sum of `share_bps` across the incoming set to equal 10_000
  (or the set to be empty, in which case the arrangement has no line
  allocation yet). Refuses to run when the parent financing is in a
  terminal state (`:option_exercised | :returned | :terminated`) for lease
  types; loans allow late line correction after `:paid_off | :terminated`.

  Locks the parent financing row before touching the child rows so
  concurrent set-lines calls serialize.
  """
  def set_lines(%Financing{} = financing, lines) when is_list(lines) do
    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)

        cond do
          not lines_editable?(current) ->
            Repo.rollback(financing_error(current, "cannot replace lines in the current status"))

          not valid_share_sum?(lines) ->
            Repo.rollback(financing_error(current, "line shares must sum to 10000 (or set must be empty)"))

          true ->
            do_replace_lines(current, lines)
        end
      end)

    case result do
      {:ok, updated_lines} ->
        audit("financing.lines_set", financing, %{"lines" => Enum.map(updated_lines, &line_audit/1)})
        {:ok, updated_lines}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def import_schedule(%Financing{} = financing, installments) when is_list(installments) do
    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)

        Enum.reduce_while(installments, {:ok, []}, fn attrs, {:ok, acc} ->
          attrs = attrs |> Map.new() |> Map.put(:financing_id, current.id)

          %FinancingSchedule{}
          |> FinancingSchedule.changeset(attrs)
          |> Repo.insert()
          |> case do
            {:ok, row} -> {:cont, {:ok, [row | acc]}}
            {:error, changeset} -> {:halt, Repo.rollback(changeset)}
          end
        end)
      end)

    case result do
      {:ok, {:ok, rows}} ->
        rows = Enum.reverse(rows)
        audit("financing.schedule_imported", financing, %{"row_count" => length(rows)})
        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def match_payment(%Financing{} = financing, transaction_id, decomposition)
      when is_binary(transaction_id) and is_map(decomposition) do
    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)
        txn = Repo.get!(Transaction, transaction_id)

        attrs =
          decomposition
          |> Map.new()
          |> Map.put(:financing_id, current.id)
          |> Map.put(:finance_transaction_id, txn.id)
          |> Map.put_new(:paid_on, txn_paid_on(txn))
          |> Map.put_new(:direction, txn.direction)
          |> Map.put_new(:settlement_amount, txn.amount_value)
          |> Map.put_new(:settlement_currency, txn.amount_currency)

        %FinancingPayment{}
        |> FinancingPayment.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, payment} -> payment
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, payment} ->
        audit("financing.payment_matched", financing, %{
          "payment_id" => payment.id,
          "finance_transaction_id" => payment.finance_transaction_id,
          "settlement_currency" => payment.settlement_currency
        })

        {:ok, payment}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def edit_payment_decomposition(payment_id, decomposition) when is_binary(payment_id) do
    result =
      Repo.transaction(fn ->
        payment = Repo.get!(FinancingPayment, payment_id)
        current_financing = fetch_locked!(payment.financing_id)

        if option_pinned?(payment, current_financing) and
             option_amount_changing?(payment, decomposition, current_financing) do
          Repo.rollback(option_pin_error("option_amount is pinned on an exercised financing"))
        else
          payment
          |> FinancingPayment.changeset(Map.new(decomposition))
          |> Repo.update()
          |> case do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end
      end)

    case result do
      {:ok, updated} ->
        audit("financing.payment_decomposition_edited", %Financing{id: updated.financing_id}, %{
          "payment_id" => updated.id
        })

        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## ------------------------------------------------------------------
  ## Lifecycle
  ## ------------------------------------------------------------------

  @doc """
  Permanently deletes a financing arrangement. Only allowed when the
  status is `:active` and no payments have been matched. Owned schedule
  rows and line rows are cleaned up in the same transaction.

  For anything that has already flowed through Finance.Transaction,
  use `mark_paid_off/2`, `return/2`, or `terminate/2` instead.
  """
  def delete(%Financing{} = financing) do
    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)

        cond do
          current.status != "active" ->
            Repo.rollback(financing_error(current, "cannot delete a financing outside active status"))

          Repo.exists?(from(p in FinancingPayment, where: p.financing_id == ^current.id)) ->
            Repo.rollback(
              financing_error(
                current,
                "has matched payments; mark paid_off, return, or terminate instead"
              )
            )

          true ->
            _ = Repo.delete_all(from(l in FinancingLine, where: l.financing_id == ^current.id))
            _ = Repo.delete_all(from(s in FinancingSchedule, where: s.financing_id == ^current.id))
            Repo.delete!(current)
            current
        end
      end)

    case result do
      {:ok, deleted} ->
        audit("financing.deleted", deleted, %{
          "provider" => deleted.provider,
          "reference" => deleted.reference,
          "type" => deleted.type
        })

        {:ok, deleted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def mark_paid_off(%Financing{} = financing, _on) do
    with_locked(financing, fn current ->
      if current.status in ["active"] do
        current
        |> Financing.status_changeset(%{status: "paid_off"})
        |> Repo.update()
      else
        {:error, financing_error(current, "must be active to be marked paid_off")}
      end
    end)
    |> after_lifecycle("financing.marked_paid_off", %{})
  end

  def exercise_option(%Financing{} = financing, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)
    option_transaction_id = Keyword.get(opts, :option_transaction_id)
    existing_payment_id = Keyword.get(opts, :existing_payment_id)
    exercise_note = Keyword.get(opts, :exercise_note)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)

        with :ok <- validate_exercisable(current),
             {:ok, payment} <-
               resolve_option_payment(current, option_transaction_id, existing_payment_id),
             lines = list_lines(current),
             :ok <- transition_lines_to_owned(lines, on),
             {:ok, updated} <-
               current
               |> Financing.status_changeset(%{status: "option_exercised"})
               |> Repo.update() do
          {updated, payment}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {updated, payment}} ->
        audit("financing.option_exercised", updated, %{
          "on" => Date.to_iso8601(on),
          "payment_id" => payment && payment.id,
          "exercise_note" => exercise_note
        })

        {:ok, preload_financing(updated)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def return(%Financing{} = financing, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)

        with :ok <- validate_returnable(current),
             lines = list_lines(current),
             :ok <- transition_lines_to_returned(lines, on),
             {:ok, updated} <-
               current
               |> Financing.status_changeset(%{status: "returned"})
               |> Repo.update() do
          updated
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, updated} ->
        audit("financing.returned", updated, %{"on" => Date.to_iso8601(on)})
        {:ok, preload_financing(updated)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def terminate(%Financing{} = financing, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)
    reason = Keyword.get(opts, :reason)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(financing.id)

        with :ok <- validate_terminable(current),
             :ok <- maybe_return_leased_assets(current, on),
             {:ok, updated} <-
               current
               |> Financing.status_changeset(%{status: "terminated"})
               |> Repo.update() do
          updated
        else
          {:error, err} -> Repo.rollback(err)
        end
      end)

    case result do
      {:ok, updated} ->
        audit("financing.terminated", updated, %{
          "on" => Date.to_iso8601(on),
          "reason" => reason
        })

        {:ok, preload_financing(updated)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## ------------------------------------------------------------------
  ## Internals
  ## ------------------------------------------------------------------

  defp preload_financing(nil), do: nil

  defp preload_financing(%Financing{} = financing) do
    Repo.preload(financing, [:lines, :schedules, documents: :document])
  end

  defp fetch_locked!(id) do
    Financing
    |> where([f], f.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp with_locked(%Financing{id: id}, fun) do
    Repo.transaction(fn ->
      current = fetch_locked!(id)

      case fun.(current) do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp after_lifecycle({:ok, %Financing{} = updated}, action, metadata) do
    audit(action, updated, metadata)
    {:ok, preload_financing(updated)}
  end

  defp after_lifecycle({:error, reason}, _action, _metadata), do: {:error, reason}

  defp lines_editable?(%Financing{status: status, type: "loan"}) when status in ["active", "paid_off", "terminated"],
    do: true

  defp lines_editable?(%Financing{status: status}) when status in ["active", "paid_off"], do: true
  defp lines_editable?(%Financing{}), do: false

  defp valid_share_sum?([]), do: true

  defp valid_share_sum?(lines) do
    Enum.reduce(lines, 0, fn line, acc -> acc + Map.get(line, :share_bps, 0) end) == 10_000
  end

  defp do_replace_lines(current, lines) do
    _ = Repo.delete_all(from(l in FinancingLine, where: l.financing_id == ^current.id))

    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      attrs = line |> Map.new() |> Map.put(:financing_id, current.id)

      %FinancingLine{}
      |> FinancingLine.changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, row} -> {:cont, {:ok, [row | acc]}}
        {:error, changeset} -> {:halt, Repo.rollback(changeset)}
      end
    end)
    |> case do
      {:ok, rows} -> Enum.reverse(rows)
      other -> other
    end
  end

  defp validate_exercisable(%Financing{type: "lease_with_purchase_option"} = f)
       when f.status in ["active", "paid_off"] do
    if is_nil(f.purchase_option_amount) do
      {:error, financing_error(f, "purchase option amount is not set")}
    else
      :ok
    end
  end

  defp validate_exercisable(f), do: {:error, financing_error(f, "cannot exercise an option in the current status/type")}

  defp validate_returnable(%Financing{type: "loan"} = f), do: {:error, financing_error(f, "loans cannot be returned")}

  defp validate_returnable(%Financing{status: status}) when status in ["active", "paid_off"], do: :ok

  defp validate_returnable(f), do: {:error, financing_error(f, "cannot return in the current status")}

  defp validate_terminable(%Financing{status: status}) when status in ["active", "paid_off"], do: :ok

  defp validate_terminable(f), do: {:error, financing_error(f, "cannot terminate in the current status")}

  defp maybe_return_leased_assets(%Financing{type: "loan"}, _on), do: :ok

  defp maybe_return_leased_assets(%Financing{} = financing, on) do
    lines = list_lines(financing)
    transition_lines_to_returned(lines, on)
  end

  defp resolve_option_payment(financing, nil, nil) do
    {:error, financing_error(financing, "option_transaction_id or existing_payment_id is required")}
  end

  defp resolve_option_payment(financing, transaction_id, nil) when is_binary(transaction_id) do
    txn = Repo.get!(Transaction, transaction_id)

    cond do
      txn.direction == "credit" ->
        {:error, financing_error(financing, "option transaction must be a debit")}

      txn.amount_currency != financing.currency ->
        {:error, financing_error(financing, "cross-currency exercise is not supported in phase B")}

      true ->
        %FinancingPayment{}
        |> FinancingPayment.changeset(%{
          financing_id: financing.id,
          finance_transaction_id: txn.id,
          paid_on: txn_paid_on(txn),
          direction: "debit",
          settlement_amount: txn.amount_value,
          settlement_currency: txn.amount_currency,
          option_amount: financing.purchase_option_amount,
          resolution_status: resolution_for_option(financing, txn.amount_value)
        })
        |> Repo.insert()
        |> case do
          {:ok, payment} -> {:ok, payment}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp resolve_option_payment(financing, nil, existing_payment_id) when is_binary(existing_payment_id) do
    payment =
      FinancingPayment
      |> where([p], p.id == ^existing_payment_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    cond do
      is_nil(payment) ->
        {:error, financing_error(financing, "existing payment not found")}

      payment.financing_id != financing.id ->
        {:error, financing_error(financing, "existing payment is not on this financing")}

      payment.direction != "debit" ->
        {:error, financing_error(financing, "existing option payment must be a debit")}

      payment.settlement_currency != financing.currency ->
        {:error, financing_error(financing, "cross-currency exercise is not supported in phase B")}

      not decimal_equal?(payment.option_amount, financing.purchase_option_amount) ->
        {:error, financing_error(financing, "existing payment option_amount does not match the strike")}

      true ->
        {:ok, payment}
    end
  end

  defp resolve_option_payment(financing, _, _),
    do: {:error, financing_error(financing, "provide exactly one of option_transaction_id or existing_payment_id")}

  defp transition_lines_to_owned(lines, on) do
    Enum.reduce_while(lines, :ok, fn %FinancingLine{asset_id: asset_id}, _ ->
      asset = Repo.get!(Asset, asset_id)

      case Assets.mark_owned_via_exercise(asset, on: on) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp transition_lines_to_returned(lines, on) do
    Enum.reduce_while(lines, :ok, fn %FinancingLine{asset_id: asset_id}, _ ->
      asset = Repo.get!(Asset, asset_id)

      case Assets.mark_returned_to_lessor(asset, on: on) do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp option_pinned?(%FinancingPayment{}, %Financing{status: "option_exercised"}), do: true
  defp option_pinned?(_, _), do: false

  defp option_amount_changing?(payment, decomposition, financing) do
    new_amount =
      case Map.get(decomposition, :option_amount) || Map.get(decomposition, "option_amount") do
        nil -> payment.option_amount
        value -> value
      end

    not decimal_equal?(new_amount, financing.purchase_option_amount)
  end

  defp option_pin_error(message) do
    %FinancingPayment{}
    |> FinancingPayment.changeset(%{})
    |> Ecto.Changeset.add_error(:option_amount, message)
  end

  defp resolution_for_option(financing, amount) do
    if decimal_equal?(amount, financing.purchase_option_amount), do: "resolved", else: "partial"
  end

  defp decimal_equal?(nil, nil), do: true
  defp decimal_equal?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)
  defp decimal_equal?(_, _), do: false

  defp financing_error(%Financing{} = f, message) do
    %Financing{}
    |> Financing.status_changeset(%{status: f.status || "active"})
    |> Ecto.Changeset.add_error(:status, message)
  end

  defp txn_paid_on(%Transaction{booked_at: nil, settled_at: %DateTime{} = dt}), do: DateTime.to_date(dt)
  defp txn_paid_on(%Transaction{booked_at: %DateTime{} = dt}), do: DateTime.to_date(dt)
  defp txn_paid_on(_), do: Date.utc_today()

  defp line_audit(%FinancingLine{} = line) do
    %{"asset_id" => line.asset_id, "share_bps" => line.share_bps}
  end

  defp audit(action, %Financing{} = financing, metadata) do
    Audit.record(action, %{
      target_type: "financing",
      target_id: financing.id,
      target_label: "#{financing.provider} #{financing.reference}",
      metadata:
        metadata
        |> sanitize()
        |> Map.merge(%{
          "path" => "#{@dashboard_prefix}/#{financing.id}",
          "financing_id" => financing.id,
          "financing_status" => financing.status
        })
    })
  end

  defp sanitize(metadata) when is_map(metadata) do
    metadata
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
