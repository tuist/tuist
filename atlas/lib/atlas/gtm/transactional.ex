defmodule Atlas.GTM.Transactional do
  @moduledoc """
  Loops-compatible transactional sends.

  Mirrors `POST https://app.loops.so/api/v1/transactional`, which takes an
  `email`, a `transactionalId` naming the template, and a `dataVariables` map
  filling that template in. The Tuist marketing site uses it to send the
  newsletter confirmation email while keeping the verification token and the
  confirmation pages on its own domain.

  Templates are addressed by an Atlas name and also by the Loops template id
  they replace, so a caller that still has the Loops id hardcoded keeps working.

  Sends are queued rather than delivered inline: a `Delivery` row is written
  with the template and its variables, and `Atlas.GTM.Workers.DeliverAutomatedEmail`
  performs it. That gives transactional email the same retry, provider
  idempotency key, and stalled-delivery recovery as the rest of Atlas email.
  """

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.GTM.Delivery
  alias Atlas.GTM.Workers.DeliverAutomatedEmail
  alias Atlas.Repo

  @newsletter_confirmation "newsletter-confirmation"

  # Atlas name => template definition. `:aliases` carries the Loops template ids
  # that used to address the same email.
  @templates %{
    @newsletter_confirmation => %{
      subject: "Confirm your Tuist newsletter subscription",
      required_variables: ["verificationUrl"],
      aliases: ["cmfglb1pe5esq2w0ixnkdou94"]
    }
  }

  @aliases Enum.reduce(@templates, %{}, fn {name, template}, acc ->
             Enum.reduce(template.aliases, acc, &Map.put(&2, &1, name))
           end)

  # A caller that times out and retries must not send a second copy. Repeats of
  # the same template, recipient, and variables inside this window return the
  # delivery that is already queued.
  @dedupe_window_seconds 15 * 60

  # A UUID collision is exceptionally unlikely, but it is recoverable. Keep the
  # retry bounded so a faulty generator still returns a useful error to callers.
  @primary_key_insert_attempts 3

  def templates, do: @templates

  def newsletter_confirmation_template, do: @newsletter_confirmation

  @doc """
  Queues a transactional email.

  Returns `{:ok, %{delivery: delivery, duplicate: boolean}}`, or
  `{:error, :unknown_transactional_id}` / `{:error, {:missing_variables, list}}`.
  """
  def send(transactional_id, email, data_variables \\ %{}) do
    with {:ok, name, template} <- fetch_template(transactional_id),
         {:ok, email} <- fetch_email(email),
         :ok <- validate_variables(template, data_variables) do
      Audit.with_context(%{interface: "api"}, fn ->
        queue(name, template, email, data_variables)
      end)
    end
  end

  defp queue(name, template, email, data_variables) do
    case recent_duplicate(name, email, data_variables) do
      %Delivery{} = delivery ->
        {:ok, %{delivery: delivery, duplicate: true}}

      nil ->
        with {:ok, delivery} <- insert_delivery(name, template, email, data_variables),
             {:ok, _job} <- enqueue(delivery) do
          Audit.record("gtm_transactional.queued", %{
            interface: "api",
            target_type: "gtm_delivery",
            target_id: delivery.id,
            target_label: delivery.recipient_email,
            metadata: %{template: name}
          })

          {:ok, %{delivery: delivery, duplicate: false}}
        end
    end
  end

  defp insert_delivery(name, template, email, data_variables) do
    attrs = %{
      kind: "transactional",
      recipient_email: email,
      subject: template.subject,
      status: "pending",
      metadata: %{"template" => name, "data_variables" => data_variables}
    }

    insert_delivery(attrs, @primary_key_insert_attempts)
  end

  defp insert_delivery(attrs, attempts_remaining) do
    %Delivery{}
    |> Delivery.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:error, changeset} when attempts_remaining > 1 ->
        if primary_key_collision?(changeset) do
          insert_delivery(attrs, attempts_remaining - 1)
        else
          {:error, changeset}
        end

      result ->
        result
    end
  end

  defp primary_key_collision?(changeset) do
    Enum.any?(changeset.errors, fn
      {:id, {_message, options}} ->
        options[:constraint] == :unique && options[:constraint_name] == "gtm_deliveries_pkey"

      _other ->
        false
    end)
  end

  defp recent_duplicate(name, email, data_variables) do
    since =
      DateTime.utc_now()
      |> DateTime.add(-@dedupe_window_seconds, :second)
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()

    # Every candidate in the window is considered, not just the most recent
    # one. Limiting to the latest would miss the duplicate as soon as another
    # transactional email to the same address landed in between.
    from(delivery in Delivery,
      where: delivery.kind == "transactional",
      where: delivery.recipient_email == ^email,
      where: delivery.status in ["pending", "delivered"],
      where: delivery.inserted_at >= ^since,
      where: fragment("? ->> 'template' = ?", delivery.metadata, ^name),
      order_by: [desc: delivery.inserted_at]
    )
    |> Repo.all()
    |> Enum.find(&(&1.metadata["data_variables"] == data_variables))
  end

  defp enqueue(%Delivery{id: id}) do
    %{"delivery_id" => id}
    |> DeliverAutomatedEmail.new()
    |> Oban.insert()
  end

  defp fetch_template(transactional_id) when is_binary(transactional_id) do
    name = Map.get(@aliases, transactional_id, transactional_id)

    case Map.fetch(@templates, name) do
      {:ok, template} -> {:ok, name, template}
      :error -> {:error, :unknown_transactional_id}
    end
  end

  defp fetch_template(_transactional_id), do: {:error, :unknown_transactional_id}

  defp fetch_email(email) when is_binary(email) do
    case String.trim(email) do
      "" -> {:error, :email_missing}
      trimmed -> {:ok, trimmed}
    end
  end

  defp fetch_email(_email), do: {:error, :email_missing}

  defp validate_variables(template, data_variables) when is_map(data_variables) do
    case Enum.reject(template.required_variables, &present?(data_variables[&1])) do
      [] -> :ok
      missing -> {:error, {:missing_variables, missing}}
    end
  end

  defp validate_variables(template, _data_variables) do
    case template.required_variables do
      [] -> :ok
      missing -> {:error, {:missing_variables, missing}}
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
