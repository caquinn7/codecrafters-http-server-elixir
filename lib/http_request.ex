defmodule HttpRequest do
  defstruct method: "", target: "", headers: %{}, body: []

  @doc """
  Reads the entire HTTP request (headers and body) from the given socket
  using the specified timeout.

  Returns either:
    {:ok, %HttpRequest{...}} or {:error, reason}.
  """
  def parse(socket, timeout) do
    with {:ok, raw_request} <- read_at_least_headers(socket, timeout),
         {:ok, req_line, headers, body} <- parse_request_head(raw_request),
         {:ok, headers} <- validate_headers(headers, req_line.http_version),
         content_len <- parse_content_length(headers),
         {:ok, full_body} <- read_remaining_body(socket, body, content_len, timeout) do
      {:ok,
       %HttpRequest{
         method: req_line.method,
         target: req_line.target,
         headers: headers,
         body: full_body
       }}
    end
  end

  # Reads from the socket until we detect "\r\n\r\n" (end of headers).
  # Some or all of the request body may be included.
  defp read_at_least_headers(socket, timeout) do
    read_at_least_headers(socket, "", timeout)
  end

  defp read_at_least_headers(socket, acc, timeout) do
    case :gen_tcp.recv(socket, 0, timeout) do
      {:ok, data} ->
        new_acc = acc <> data

        if String.contains?(new_acc, "\r\n\r\n") do
          {:ok, new_acc}
        else
          read_at_least_headers(socket, new_acc, timeout)
        end

      error ->
        error
    end
  end

  defp parse_request_head(raw_request) do
    with [head, body] <- String.split(raw_request, "\r\n\r\n", parts: 2),
         head_lines when head_lines != [] <- String.split(head, "\r\n"),
         [req_line | header_lines] <- head_lines,
         req_parts when length(req_parts) == 3 <- String.split(req_line, " ", parts: 3) do
      [method, target, http_version] = req_parts
      req_line = %{method: method, target: target, http_version: http_version}

      headers =
        header_lines
        |> Enum.map(fn line ->
          case String.split(line, ": ", parts: 2) do
            [k, v] -> {k, v}
            [k] -> {k, ""}
          end
        end)
        |> Enum.into(%{})

      {:ok, req_line, headers, body}
    else
      head_lines when is_list(head_lines) and head_lines == [] ->
        {:error, "Empty request head."}

      req_parts when is_list(req_parts) and length(req_parts) != 3 ->
        {:error, "Malformed request line."}

      _ ->
        {:error, "Unknown parsing error."}
    end
  end

  defp validate_headers(%{"Host" => _} = headers, _http_version), do: {:ok, headers}
  defp validate_headers(_headers, _httpVersion), do: {:error, "Missing required Host header."}

  defp parse_content_length(headers) do
    headers
    |> Map.get("Content-Length", "0")
    |> Integer.parse()
    |> case do
      {value, _} when value >= 0 -> value
      _ -> 0
    end
  end

  # Reads the body from the socket if needed.
  # 'received_body' is the portion of the body we already received after headers.
  defp read_remaining_body(socket, received_body, content_len, timeout) do
    remaining_byte_count = content_len - byte_size(received_body)

    if remaining_byte_count > 0 do
      case :gen_tcp.recv(socket, remaining_byte_count, timeout) do
        {:ok, chunk} ->
          read_remaining_body(socket, received_body <> chunk, content_len, timeout)

        error ->
          error
      end
    else
      {:ok, received_body}
    end
  end
end
