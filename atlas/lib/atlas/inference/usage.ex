defmodule Atlas.Inference.Usage do
  @moduledoc """
  Token usage captured from an inference relay response.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Token

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @operations ~w(chat_completion embedding)

  schema "inference_usages" do
    field :operation, :string, default: "chat_completion"
    field :upstream_provider, :string
    field :upstream_model, :string
    field :status, :integer
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :cost_usd, :decimal, default: Decimal.new(0)

    belongs_to :model_binding, ModelBinding
    belongs_to :token, Token

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :operation,
      :upstream_provider,
      :upstream_model,
      :status,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :cost_usd
    ])
    |> validate_required([
      :operation,
      :upstream_provider,
      :upstream_model,
      :status,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :cost_usd
    ])
    |> validate_inclusion(:operation, @operations)
    |> validate_number(:status, greater_than_or_equal_to: 100)
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:model_binding_id)
    |> foreign_key_constraint(:token_id)
  end
end
