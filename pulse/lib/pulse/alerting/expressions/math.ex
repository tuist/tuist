defmodule Pulse.Alerting.Expressions.Math do
  @moduledoc false
  @precedence %{
    "||" => 1,
    "&&" => 2,
    "==" => 3,
    "!=" => 3,
    ">" => 3,
    ">=" => 3,
    "<" => 3,
    "<=" => 3,
    "+" => 4,
    "-" => 4,
    "*" => 5,
    "/" => 5,
    "%" => 5,
    "**" => 6
  }
  @token ~r/\A(?:\s+|\$\{[A-Za-z_][A-Za-z_0-9]*\}|\$[A-Za-z_][A-Za-z_0-9]*|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|\*\*|&&|\|\||==|!=|>=|<=|[+*\/%<>!()\-])/

  def parse(text) when is_binary(text) and byte_size(text) in 1..16_384 do
    with {:ok, tokens} <- tokenize(text, [], 0),
         {:ok, ast, []} <- expression(tokens, 1, 0),
         {:ok, size, refs} <- inspect_ast(ast, 0) do
      {:ok, ast, size, Enum.sort(Enum.uniq(refs))}
    else
      _ -> {:error, :invalid_expression}
    end
  rescue
    _ -> {:error, :invalid_expression}
  end

  def parse(_), do: {:error, :invalid_expression}

  defp tokenize("", acc, _), do: {:ok, Enum.reverse(acc)}
  defp tokenize(_, _, count) when count >= 256, do: :error

  defp tokenize(text, acc, count) do
    case Regex.run(@token, text) do
      [token] ->
        rest = binary_part(text, byte_size(token), byte_size(text) - byte_size(token))

        case token(token) do
          :space -> tokenize(rest, acc, count)
          {:ok, value} -> tokenize(rest, [value | acc], count + 1)
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp token("${" <> rest), do: {:ok, {:ref, binary_part(rest, 0, byte_size(rest) - 1)}}
  defp token("$" <> ref), do: {:ok, {:ref, ref}}
  defp token("("), do: {:ok, :left}
  defp token(")"), do: {:ok, :right}

  defp token(value) do
    cond do
      String.trim(value) == "" ->
        :space

      Map.has_key?(@precedence, value) or value == "!" ->
        {:ok, {:op, value}}

      byte_size(value) <= 1024 ->
        number_token(value)

      true ->
        :error
    end
  end

  # Grafana's parser first uses Go ParseUint(base=0): leading-zero integral
  # literals are octal when valid uint64, otherwise it tries ParseFloat.
  defp number_token(value) do
    if Regex.match?(~r/\A0[0-7]+\z/, value) do
      {integer, ""} = Integer.parse(value, 8)
      if integer <= 18_446_744_073_709_551_615, do: {:ok, {:literal, integer / 1}}, else: decimal_token(value)
    else
      decimal_token(value)
    end
  end

  defp decimal_token(value) do
    value = if String.starts_with?(value, "."), do: "0" <> value, else: value
    value = Regex.replace(~r/\.(?=[eE]|\z)/, value, ".0")

    case Float.parse(value) do
      {number, ""} -> {:ok, {:literal, number}}
      _ -> :error
    end
  end

  defp expression(_, _, depth) when depth > 64, do: :error

  defp expression(tokens, precedence, depth) do
    with {:ok, first, remaining} <- prefix(tokens, depth), do: continue(first, remaining, precedence, depth)
  end

  defp prefix([{:op, op} | rest], depth) when op in ["-", "!"] do
    with {:ok, ast, remaining} <- expression(rest, 7, depth + 1), do: {:ok, {:unary, op, ast}, remaining}
  end

  defp prefix([:left | rest], depth) do
    with {:ok, ast, [:right | remaining]} <- expression(rest, 1, depth + 1), do: {:ok, ast, remaining}
  end

  defp prefix([{kind, _} = token | rest], _) when kind in [:literal, :ref], do: {:ok, token, rest}
  defp prefix(_, _), do: :error

  defp continue(first, [{:op, op} | rest] = remaining, minimum, depth) do
    priority = @precedence[op]

    if priority && priority >= minimum do
      # Grafana math exponentiation is left-associative, unlike PromQL.
      with {:ok, right, remaining} <- expression(rest, priority + 1, depth + 1),
           do: continue({:binary, op, first, right}, remaining, minimum, depth)
    else
      {:ok, first, remaining}
    end
  end

  defp continue(first, rest, _, _), do: {:ok, first, rest}

  defp inspect_ast(_, depth) when depth > 64, do: :error
  defp inspect_ast({:literal, _}, _), do: {:ok, 1, []}
  defp inspect_ast({:ref, ref}, _) when byte_size(ref) <= 128, do: {:ok, 1, [ref]}
  defp inspect_ast({:ref, _}, _), do: :error

  defp inspect_ast({:unary, _, ast}, depth) do
    with {:ok, size, refs} <- inspect_ast(ast, depth + 1), do: {:ok, size + 1, refs}
  end

  defp inspect_ast({:binary, _, left, right}, depth) do
    with {:ok, a, refs_a} <- inspect_ast(left, depth + 1),
         {:ok, b, refs_b} <- inspect_ast(right, depth + 1),
         do: {:ok, a + b + 1, refs_a ++ refs_b}
  end
end
