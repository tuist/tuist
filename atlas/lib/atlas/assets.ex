defmodule Atlas.Assets do
  @moduledoc """
  Hardware inventory: laptops, servers, network gear, monitors, UPS units,
  peripherals. Tracks acquisition cost, custody intervals, physical events,
  and computes estimated book value on demand.

  Lifecycle mutations reload each asset under `SELECT ... FOR UPDATE`
  inside a transaction, validate the transition against the reloaded row,
  and record an audit entry after the transaction commits. See
  `docs/hardware-inventory-proposal.md` for the full design.
  """

  import Ecto.Query

  alias Atlas.Assets.Asset
  alias Atlas.Assets.Assignment
  alias Atlas.Assets.BookValue
  alias Atlas.Assets.DataCenter
  alias Atlas.Assets.Event
  alias Atlas.Audit
  alias Atlas.Finance.FinancingLine
  alias Atlas.Repo
  alias Atlas.Users.User

  @asset_dashboard_prefix "/hardware"

  ## ------------------------------------------------------------------
  ## Reads
  ## ------------------------------------------------------------------

  def get_asset(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> Repo.get(Asset, id) |> maybe_preload_asset()
      :error -> nil
    end
  end

  def get_asset(_id), do: nil

  def get_asset!(id) when is_binary(id) do
    Asset
    |> Repo.get!(id)
    |> maybe_preload_asset()
  end

  def list_assets(params \\ %{}, opts \\ []) do
    Asset
    |> maybe_filter_query(Keyword.get(opts, :query))
    |> preload_asset_relations()
    |> order_by([a], asc: a.name, asc: a.id)
    |> Flop.run(struct(Flop, params), for: Asset)
  end

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query

  defp maybe_filter_query(query, value) when is_binary(value) do
    pattern = "%#{String.replace(value, "%", "\\%")}%"

    where(
      query,
      [a],
      ilike(a.name, ^pattern) or ilike(a.serial_number, ^pattern) or ilike(a.asset_tag, ^pattern) or
        ilike(a.manufacturer, ^pattern) or ilike(a.model, ^pattern)
    )
  end

  def list_assets_assigned_to(%User{id: user_id}, params \\ %{}) do
    Asset
    |> where([a], a.assigned_to_id == ^user_id)
    |> preload_asset_relations()
    |> order_by([a], asc: a.name, asc: a.id)
    |> Flop.run(struct(Flop, params), for: Asset)
  end

  def list_assignments(%Asset{id: asset_id}, params \\ %{}) do
    Assignment
    |> where([a], a.asset_id == ^asset_id)
    |> preload(:user)
    |> order_by([a], desc: a.assigned_on, desc: a.id)
    |> Flop.run(struct(Flop, params), for: Assignment)
  end

  def list_events(%Asset{id: asset_id}, params \\ %{}) do
    Event
    |> where([e], e.asset_id == ^asset_id)
    |> order_by([e], desc: e.occurred_on, desc: e.id)
    |> Flop.run(struct(Flop, params), for: Event)
  end

  ## ------------------------------------------------------------------
  ## Changesets exposed for LiveView forms
  ## ------------------------------------------------------------------

  def change_asset(attrs \\ %{}), do: Asset.create_changeset(%Asset{}, attrs)
  def change_asset(%Asset{} = asset, attrs), do: Asset.metadata_changeset(asset, attrs)

  ## ------------------------------------------------------------------
  ## Creation and metadata
  ## ------------------------------------------------------------------

  def create_asset(attrs) when is_map(attrs) do
    %Asset{}
    |> Asset.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, asset} ->
        audit_asset("asset.created", asset, %{
          "category" => asset.category,
          "acquisition_cost" => decimal_to_string(asset.acquisition_cost),
          "acquisition_currency" => asset.acquisition_currency
        })

        {:ok, maybe_preload_asset(asset)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Permanently deletes an asset. Only allowed when the asset has no
  assignments, no events, and is not referenced by any financing line.
  For a device that already has any lifecycle history, use `retire/2` or
  `dispose/2` instead.
  """
  def delete_asset(%Asset{} = asset) do
    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)

        cond do
          Repo.exists?(from(a in Assignment, where: a.asset_id == ^current.id)) ->
            Repo.rollback(deletion_error(current, "has assignment history; retire or dispose instead"))

          Repo.exists?(from(e in Event, where: e.asset_id == ^current.id)) ->
            Repo.rollback(deletion_error(current, "has recorded events; retire or dispose instead"))

          Repo.exists?(from(l in FinancingLine, where: l.asset_id == ^current.id)) ->
            Repo.rollback(deletion_error(current, "is linked to a financing arrangement; remove the line first"))

          true ->
            Repo.delete!(current)
            current
        end
      end)

    case result do
      {:ok, deleted} ->
        audit_asset("asset.deleted", deleted, %{
          "name" => deleted.name,
          "asset_tag" => deleted.asset_tag,
          "category" => deleted.category
        })

        {:ok, deleted}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp deletion_error(%Asset{} = asset, message) do
    %Asset{}
    |> Asset.metadata_changeset(%{})
    |> Ecto.Changeset.add_error(:base, "#{asset.name}: #{message}")
  end

  def edit_metadata(%Asset{} = asset, attrs) when is_map(attrs) do
    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)
        previous_warranty = current.warranty_end_on

        current
        |> Asset.metadata_changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {updated, previous_warranty}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {updated, previous_warranty}} ->
        maybe_warranty_edit_audit(updated, previous_warranty)

        audit_asset("asset.metadata_edited", updated, %{
          "changed_fields" =>
            attrs
            |> Enum.map(fn {k, _v} -> to_string(k) end)
            |> Enum.sort()
        })

        {:ok, maybe_preload_asset(updated)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## ------------------------------------------------------------------
  ## Lifecycle
  ## ------------------------------------------------------------------

  def place_in_service(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    with_locked_asset(asset, fn current ->
      cond do
        current.state == "in_service" ->
          {:error, transition_error(current, "already in service")}

        current.state not in ["in_storage", "in_repair"] ->
          {:error, transition_error(current, "must be in storage or repair to be placed in service")}

        true ->
          apply_lifecycle_change(current, %{
            state: "in_service",
            placed_in_service_on: current.placed_in_service_on || on,
            pre_repair_state: nil
          })
      end
    end)
    |> after_lifecycle("asset.placed_in_service", %{"placed_in_service_on" => Date.to_iso8601(on)})
  end

  def assign(%Asset{} = asset, %User{} = user, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)
    notes = Keyword.get(opts, :notes)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)

        cond do
          current.state not in ["in_storage", "in_service"] ->
            Repo.rollback(transition_error(current, "cannot be assigned in its current state"))

          not is_nil(current.assigned_to_id) ->
            Repo.rollback(transition_error(current, "already has an open assignment"))

          reject_overlap?(current.id, on) ->
            Repo.rollback(overlap_error())

          true ->
            do_assign(current, user, on, notes)
        end
      end)

    result
    |> case do
      {:ok, {updated, _assignment}} ->
        audit_asset("asset.assigned", updated, %{
          "assigned_on" => Date.to_iso8601(on),
          "assigned_to_id" => user.id,
          "assigned_to_label" => user_label(user)
        })

        {:ok, maybe_preload_asset(updated)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def return_asset(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)
    notes = Keyword.get(opts, :notes)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)

        cond do
          current.state != "in_service" ->
            Repo.rollback(transition_error(current, "is not currently in service"))

          is_nil(current.assigned_to_id) ->
            Repo.rollback(transition_error(current, "has no open assignment"))

          true ->
            do_return(current, on, notes)
        end
      end)

    case result do
      {:ok, updated} ->
        audit_asset("asset.returned", updated, %{"returned_on" => Date.to_iso8601(on)})
        {:ok, maybe_preload_asset(updated)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def mark_in_repair(%Asset{} = asset, opts) when is_list(opts) do
    _on = Keyword.fetch!(opts, :on)

    with_locked_asset(asset, fn current ->
      cond do
        current.state == "in_repair" ->
          {:error, transition_error(current, "already in repair")}

        current.state not in ["in_storage", "in_service"] ->
          {:error, transition_error(current, "cannot enter repair in its current state")}

        true ->
          apply_lifecycle_change(current, %{
            state: "in_repair",
            pre_repair_state: current.state
          })
      end
    end)
    |> after_lifecycle("asset.marked_in_repair", %{})
  end

  def mark_repaired(%Asset{} = asset, opts) when is_list(opts) do
    _on = Keyword.fetch!(opts, :on)

    with_locked_asset(asset, fn current ->
      cond do
        current.state != "in_repair" ->
          {:error, transition_error(current, "is not in repair")}

        is_nil(current.pre_repair_state) ->
          {:error, transition_error(current, "has no recorded pre-repair state")}

        true ->
          apply_lifecycle_change(current, %{
            state: current.pre_repair_state,
            pre_repair_state: nil
          })
      end
    end)
    |> after_lifecycle("asset.marked_repaired", %{})
  end

  def mark_lost(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    with_locked_asset(asset, fn current ->
      if current.state in ["retired", "disposed", "lost"] do
        {:error, transition_error(current, "cannot be marked lost in its current state")}
      else
        apply_lifecycle_change(current, %{
          state: "lost",
          pre_loss_state: current.state,
          lost_on: on,
          recovered_on: nil
        })
      end
    end)
    |> after_lifecycle("asset.marked_lost", %{"lost_on" => Date.to_iso8601(on)})
  end

  def recover(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    with_locked_asset(asset, fn current ->
      cond do
        current.state != "lost" ->
          {:error, transition_error(current, "is not currently lost")}

        is_nil(current.pre_loss_state) ->
          {:error, transition_error(current, "has no recorded pre-loss state")}

        true ->
          apply_lifecycle_change(current, %{
            state: current.pre_loss_state,
            pre_loss_state: nil,
            recovered_on: on
          })
      end
    end)
    |> after_lifecycle("asset.recovered", %{"recovered_on" => Date.to_iso8601(on)})
  end

  def retire(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)

        cond do
          current.state == "retired" ->
            Repo.rollback(transition_error(current, "is already retired"))

          current.state == "disposed" ->
            Repo.rollback(transition_error(current, "cannot be retired after disposal"))

          true ->
            with :ok <- maybe_close_open_assignment(current, on),
                 {:ok, updated} <-
                   apply_lifecycle_change_locked(current, %{
                     state: "retired",
                     retired_on: on,
                     assigned_to_id: nil,
                     pre_loss_state: nil,
                     pre_repair_state: nil
                   }) do
              updated
            else
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end)

    case result do
      {:ok, updated} ->
        audit_asset("asset.retired", updated, %{"retired_on" => Date.to_iso8601(on)})
        {:ok, maybe_preload_asset(updated)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Transitions a leased asset to `:returned_to_lessor`, invoked from the
  financing return workflow. Does not delegate to `return_asset/2` (which
  requires `:in_service` and moves the asset to `:in_storage`). Closes any
  open assignment atomically; preserves `retired_on` if set. Marking a
  retired asset as returned-to-lessor is legal (the phase-1 constraint was
  amended to allow this pairing).
  """
  def mark_returned_to_lessor(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)

        cond do
          current.state == "returned_to_lessor" ->
            Repo.rollback(transition_error(current, "is already returned to lessor"))

          current.state == "disposed" ->
            Repo.rollback(transition_error(current, "cannot be returned after disposal"))

          current.state == "lost" ->
            Repo.rollback(transition_error(current, "cannot be returned while lost"))

          true ->
            with :ok <- maybe_close_open_assignment(current, on),
                 {:ok, updated} <-
                   apply_lifecycle_change_locked(current, %{
                     state: "returned_to_lessor",
                     assigned_to_id: nil
                   }) do
              updated
            else
              {:error, reason} -> Repo.rollback(reason)
            end
        end
      end)

    case result do
      {:ok, updated} ->
        audit_asset("asset.returned_to_lessor", updated, %{
          "returned_to_lessor_on" => Date.to_iso8601(on)
        })

        {:ok, maybe_preload_asset(updated)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Called from the purchase-option exercise flow. Flips ownership to `:owned`,
  sets `ownership_acquired_on`, and backfills `purchased_on` if null.
  Preserves `placed_in_service_on` and `acquisition_cost`. Runs inside the
  caller's transaction (the caller is expected to have already locked the
  asset row).
  """
  def mark_owned_via_exercise(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)

    changes =
      %{ownership: "owned", ownership_acquired_on: on}
      |> maybe_backfill_purchased_on(asset, on)

    asset
    |> Asset.lifecycle_changeset(changes)
    |> Repo.update()
  end

  defp maybe_backfill_purchased_on(changes, %Asset{purchased_on: nil}, on), do: Map.put(changes, :purchased_on, on)

  defp maybe_backfill_purchased_on(changes, %Asset{}, _on), do: changes

  def dispose(%Asset{} = asset, opts) when is_list(opts) do
    on = Keyword.fetch!(opts, :on)
    proceeds = Keyword.get(opts, :proceeds)
    currency = Keyword.get(opts, :currency)

    with_locked_asset(asset, fn current ->
      cond do
        current.state != "retired" ->
          {:error, transition_error(current, "must be retired before disposal")}

        Date.before?(on, current.retired_on) ->
          {:error, transition_error(current, "disposal date must be on or after retirement date")}

        true ->
          apply_lifecycle_change(current, %{
            state: "disposed",
            disposed_on: on,
            disposal_proceeds: proceeds,
            disposal_currency: currency
          })
      end
    end)
    |> after_lifecycle("asset.disposed", %{
      "disposed_on" => Date.to_iso8601(on),
      "proceeds" => decimal_to_string(proceeds),
      "currency" => currency
    })
  end

  ## ------------------------------------------------------------------
  ## Events
  ## ------------------------------------------------------------------

  def record_repair(%Asset{} = asset, attrs) do
    attrs
    |> Map.put(:asset_id, asset.id)
    |> Map.put(:event_type, "repaired")
    |> insert_event(asset, "asset.repair_recorded")
  end

  def record_incident(%Asset{} = asset, attrs) do
    attrs
    |> Map.put(:asset_id, asset.id)
    |> Map.put(:event_type, "incident")
    |> insert_event(asset, "asset.incident_recorded")
  end

  def record_note(%Asset{} = asset, attrs) do
    attrs
    |> Map.put(:asset_id, asset.id)
    |> Map.put(:event_type, "note")
    |> insert_event(asset, "asset.note_recorded")
  end

  def record_warranty_extension(%Asset{} = asset, attrs) do
    new_warranty_end_on = Map.get(attrs, :new_warranty_end_on) || Map.get(attrs, "new_warranty_end_on")

    result =
      Repo.transaction(fn ->
        current = fetch_locked!(asset.id)
        previous = current.warranty_end_on

        event_attrs =
          attrs
          |> Map.put(:asset_id, current.id)
          |> Map.put(:event_type, "warranty_extended")
          |> Map.put_new(:previous_warranty_end_on, previous)

        with {:ok, updated} <-
               current
               |> Asset.lifecycle_changeset(%{warranty_end_on: new_warranty_end_on})
               |> Repo.update(),
             {:ok, event} <-
               %Event{}
               |> Event.changeset(event_attrs)
               |> Repo.insert() do
          {updated, event, previous}
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {updated, event, previous}} ->
        audit_asset("asset.warranty_extended", updated, %{
          "previous_warranty_end_on" => date_to_iso(previous),
          "new_warranty_end_on" => date_to_iso(event.new_warranty_end_on)
        })

        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## ------------------------------------------------------------------
  ## Derived
  ## ------------------------------------------------------------------

  def book_value_at(%Asset{} = asset, on: %Date{} = date), do: BookValue.at(asset, on: date)

  def fleet_eligible?(%Asset{state: state}, _on) when state in ["retired", "disposed", "lost", "returned_to_lessor"],
    do: false

  def fleet_eligible?(%Asset{}, _on), do: true

  @doc """
  Returns totals grouped by `{category, acquisition_currency}` for all
  currently fleet-eligible assets. Only sums like currencies; never
  cross-currency.
  """
  def book_value_report(on: %Date{} = date) do
    Asset
    |> where([a], a.state not in ["retired", "disposed", "lost", "returned_to_lessor"])
    |> Repo.all()
    |> Enum.reduce(%{}, fn asset, acc ->
      case book_value_at(asset, on: date) do
        {:ok, value, currency} ->
          Map.update(acc, {asset.category, currency}, {value, 1}, fn {sum, count} ->
            {Decimal.add(sum, value), count + 1}
          end)

        {:error, _reason} ->
          Map.update(acc, {asset.category, "unknown"}, {Decimal.new(0), 1}, fn {sum, count} ->
            {sum, count + 1}
          end)
      end
    end)
  end

  ## ------------------------------------------------------------------
  ## Data centers
  ## ------------------------------------------------------------------

  def list_data_centers(params \\ %{}) do
    DataCenter
    |> order_by([d], asc: d.name, asc: d.id)
    |> Flop.run(struct(Flop, params), for: DataCenter)
  end

  def get_data_center(id) when is_binary(id) do
    case Atlas.UUIDv7.cast(id) do
      {:ok, id} -> Repo.get(DataCenter, id)
      :error -> nil
    end
  end

  def get_data_center(_id), do: nil

  def get_data_center!(id) when is_binary(id), do: Repo.get!(DataCenter, id)

  def change_data_center(attrs \\ %{}), do: DataCenter.create_changeset(%DataCenter{}, attrs)

  def change_data_center(%DataCenter{} = data_center, attrs), do: DataCenter.metadata_changeset(data_center, attrs)

  def create_data_center(attrs) when is_map(attrs) do
    %DataCenter{}
    |> DataCenter.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, data_center} = ok ->
        audit_data_center("data_center.created", data_center, %{
          "name" => data_center.name,
          "provider" => data_center.provider,
          "city" => data_center.city,
          "country" => data_center.country
        })

        ok

      other ->
        other
    end
  end

  def edit_data_center(%DataCenter{} = data_center, attrs) when is_map(attrs) do
    data_center
    |> DataCenter.metadata_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        audit_data_center("data_center.metadata_edited", updated, %{
          "changed_fields" =>
            attrs
            |> Enum.map(fn {k, _v} -> to_string(k) end)
            |> Enum.sort()
        })

        ok

      other ->
        other
    end
  end

  def decommission_data_center(%DataCenter{} = data_center) do
    hosted_count = data_center_asset_count(data_center)

    if hosted_count > 0 do
      changeset =
        data_center
        |> DataCenter.status_changeset(%{status: "decommissioned"})
        |> Ecto.Changeset.add_error(:base, "hosts #{hosted_count} active assets; move or return them first")

      {:error, changeset}
    else
      data_center
      |> DataCenter.status_changeset(%{status: "decommissioned"})
      |> Repo.update()
      |> case do
        {:ok, updated} = ok ->
          audit_data_center("data_center.decommissioned", updated, %{"name" => updated.name})
          ok

        other ->
          other
      end
    end
  end

  def delete_data_center(%DataCenter{} = data_center) do
    if data_center_asset_count(data_center) > 0 do
      changeset =
        data_center
        |> DataCenter.metadata_changeset(%{})
        |> Ecto.Changeset.add_error(:base, "hosts assets; move them or decommission instead")

      {:error, changeset}
    else
      case Repo.delete(data_center) do
        {:ok, deleted} = ok ->
          audit_data_center("data_center.deleted", deleted, %{"name" => deleted.name})
          ok

        other ->
          other
      end
    end
  end

  def install_asset_in_data_center(%Asset{} = asset, %DataCenter{} = data_center, opts \\ []) do
    location_detail = Keyword.get(opts, :location_detail)

    attrs = %{
      location: "data_center",
      data_center_id: data_center.id,
      location_detail: location_detail
    }

    edit_metadata(asset, attrs)
  end

  def list_assets_in_data_center(%DataCenter{id: id}) do
    Asset
    |> where([a], a.data_center_id == ^id)
    |> preload_asset_relations()
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  defp data_center_asset_count(%DataCenter{id: id}) do
    Repo.aggregate(from(a in Asset, where: a.data_center_id == ^id), :count, :id)
  end

  defp audit_data_center(action, %DataCenter{} = data_center, metadata) do
    Audit.record(action, %{
      target_type: "asset_data_center",
      target_id: data_center.id,
      target_label: data_center.name,
      metadata: metadata
    })
  end

  ## ------------------------------------------------------------------
  ## Internals
  ## ------------------------------------------------------------------

  defp preload_asset_relations(query) do
    preload(query, [:assigned_to, :data_center, :finance_transaction, :finance_invoice, :purchase_document])
  end

  defp maybe_preload_asset(nil), do: nil

  defp maybe_preload_asset(%Asset{} = asset) do
    Repo.preload(asset, [:assigned_to, :data_center, :finance_transaction, :finance_invoice, :purchase_document])
  end

  defp fetch_locked!(id) do
    Asset
    |> where([a], a.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
  end

  defp with_locked_asset(%Asset{id: id}, fun) do
    Repo.transaction(fn ->
      current = fetch_locked!(id)

      case fun.(current) do
        {:ok, updated} -> updated
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_lifecycle_change(%Asset{} = current, changes) do
    current
    |> Asset.lifecycle_changeset(changes)
    |> Repo.update()
    |> case do
      {:ok, updated} -> {:ok, updated}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_lifecycle_change_locked(%Asset{} = current, changes) do
    apply_lifecycle_change(current, changes)
  end

  defp do_assign(%Asset{} = current, %User{} = user, on, notes) do
    changes = %{
      state: "in_service",
      assigned_to_id: user.id,
      placed_in_service_on: current.placed_in_service_on || on
    }

    with {:ok, updated} <- apply_lifecycle_change_locked(current, changes),
         {:ok, assignment} <-
           %Assignment{}
           |> Assignment.open_changeset(%{
             asset_id: updated.id,
             user_id: user.id,
             user_label_snapshot: user_label(user),
             assigned_on: on,
             notes: notes
           })
           |> Repo.insert() do
      {updated, assignment}
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp do_return(%Asset{} = current, on, notes) do
    open =
      Assignment
      |> where([a], a.asset_id == ^current.id and is_nil(a.returned_on))
      |> Repo.one()

    if is_nil(open) do
      Repo.rollback(transition_error(current, "has no open assignment to close"))
    else
      with {:ok, _closed} <-
             open
             |> Assignment.close_changeset(%{returned_on: on, notes: notes || open.notes})
             |> Repo.update(),
           {:ok, updated} <-
             apply_lifecycle_change_locked(current, %{
               state: "in_storage",
               assigned_to_id: nil
             }) do
        updated
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
  end

  defp maybe_close_open_assignment(%Asset{assigned_to_id: nil}, _on), do: :ok

  defp maybe_close_open_assignment(%Asset{id: asset_id}, on) do
    open =
      Assignment
      |> where([a], a.asset_id == ^asset_id and is_nil(a.returned_on))
      |> Repo.one()

    case open do
      nil ->
        :ok

      %Assignment{} = assignment ->
        assignment
        |> Assignment.close_changeset(%{returned_on: on})
        |> Repo.update()
        |> case do
          {:ok, _closed} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp reject_overlap?(asset_id, %Date{} = on) do
    Assignment
    |> where([a], a.asset_id == ^asset_id)
    |> where(
      [a],
      a.assigned_on <= ^on and (is_nil(a.returned_on) or a.returned_on >= ^on)
    )
    |> Repo.exists?()
  end

  defp overlap_error do
    %Asset{}
    |> Asset.metadata_changeset(%{})
    |> Ecto.Changeset.add_error(:assigned_on, "overlaps an existing assignment for this asset")
  end

  defp transition_error(%Asset{state: state}, message) do
    %Asset{}
    |> Asset.metadata_changeset(%{})
    |> Ecto.Changeset.add_error(:state, "#{message} (current state: #{state})")
  end

  defp insert_event(attrs, %Asset{} = asset, action) do
    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        audit_asset(action, asset, %{
          "event_id" => event.id,
          "event_type" => event.event_type,
          "occurred_on" => Date.to_iso8601(event.occurred_on)
        })

        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp after_lifecycle({:ok, %Asset{} = updated}, action, metadata) do
    audit_asset(action, updated, metadata)
    {:ok, maybe_preload_asset(updated)}
  end

  defp after_lifecycle({:error, reason}, _action, _metadata), do: {:error, reason}

  defp maybe_warranty_edit_audit(%Asset{warranty_end_on: same}, same), do: :ok

  defp maybe_warranty_edit_audit(%Asset{} = updated, previous) do
    audit_asset("asset.warranty_edited", updated, %{
      "previous_warranty_end_on" => date_to_iso(previous),
      "new_warranty_end_on" => date_to_iso(updated.warranty_end_on)
    })
  end

  defp audit_asset(action, %Asset{} = asset, metadata) do
    Audit.record(action, %{
      target_type: "asset",
      target_id: asset.id,
      target_label: asset.name,
      metadata:
        Map.merge(sanitize_metadata(metadata), %{
          "path" => "#{@asset_dashboard_prefix}/#{asset.id}",
          "asset_id" => asset.id,
          "asset_state" => asset.state
        })
    })
  end

  defp sanitize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp date_to_iso(nil), do: nil
  defp date_to_iso(%Date{} = date), do: Date.to_iso8601(date)

  defp decimal_to_string(nil), do: nil
  defp decimal_to_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp user_label(%User{name: name, email: email}) when is_binary(name), do: "#{name} <#{email}>"
  defp user_label(%User{email: email}), do: email
end
