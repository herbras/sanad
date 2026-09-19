defmodule Sanad.Cogs.Chat.Stream do
  @moduledoc """
  Decodes the server-sent event streams the chat providers return.

  All four frame their streams as SSE `data:` lines, but each puts the text
  somewhere different, and a chunk can split a line anywhere — including in
  the middle of a JSON object. `decode/3` therefore takes the leftover buffer
  and returns it, so the caller can feed chunks in as they arrive:

      {deltas, buffer} = Stream.decode(:openai, buffer, chunk)

  It is a pure function, which is what makes the framing testable without a
  server.
  """

  @type provider :: :openai | :anthropic | :gemini | :perplexity

  @doc """
  Decodes one chunk, returning the text deltas it completed and whatever is
  left over for the next chunk.
  """
  @spec decode(provider(), binary(), binary()) :: {[binary()], binary()}
  def decode(provider, buffer, chunk) do
    {lines, rest} = split_lines(buffer <> chunk)

    deltas =
      lines
      |> Enum.flat_map(&payload/1)
      |> Enum.flat_map(&text(provider, &1))
      |> Enum.reject(&(&1 == ""))

    {deltas, rest}
  end

  @doc "Flushes a trailing line left in the buffer when the stream ends."
  @spec finish(provider(), binary()) :: [binary()]
  def finish(provider, buffer) do
    {deltas, _rest} = decode(provider, buffer, "\n")
    deltas
  end

  defp split_lines(binary) do
    case String.split(binary, "\n") do
      [only] -> {[], only}
      parts -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  # SSE carries comments (`:`), event names and blank separators as well; only
  # `data:` lines hold payloads, and `[DONE]` is a terminator, not JSON.
  defp payload(line) do
    case String.trim(line) do
      "data:" <> rest ->
        case String.trim(rest) do
          "[DONE]" -> []
          "" -> []
          json -> decode_json(json)
        end

      _other ->
        []
    end
  end

  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> [decoded]
      _ -> []
    end
  end

  defp text(provider, %{"choices" => [%{"delta" => delta} | _]})
       when provider in [:openai, :perplexity] and is_map(delta) do
    case delta["content"] do
      content when is_binary(content) -> [content]
      _ -> []
    end
  end

  defp text(:anthropic, %{"type" => "content_block_delta", "delta" => %{"text" => text}})
       when is_binary(text) do
    [text]
  end

  defp text(:gemini, %{"candidates" => [%{"content" => %{"parts" => parts}} | _]})
       when is_list(parts) do
    Enum.flat_map(parts, fn
      %{"text" => text} when is_binary(text) -> [text]
      _ -> []
    end)
  end

  defp text(_provider, _event), do: []
end
