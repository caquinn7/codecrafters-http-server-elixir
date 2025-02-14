defmodule HttpResponse do
  defstruct status_code: "", headers: %{}, body: []

  @doc """
  Generates a complete HTTP/1.1 response string, including the status line,
  headers, and body.

  ## Parameters

    * `status_code` – An integer representing the HTTP status code (e.g., 200, 404).
    * `opts` (keyword list) – Optional parameters:
      * `:headers` (map) – Additional headers to include (defaults to `%{}`).
      * `:content_type` (string) – The `Content-Type` header (defaults to `"text/plain"`) when the body is not empty.
      * `:body` (iodata) – The response body, which can be a string, binary, or list of binaries.

  ## Returns

  A string conforming to the HTTP/1.1 format, containing:
    * The status line – e.g., `"HTTP/1.1 200 OK"`.
    * Headers, including `Content-Length` computed from the body size.
    * A blank line (`\\r\\n`) separating the headers from the body.
    * The response body itself.

  ## Examples

      iex> HttpResponse.new(200, body: "Hello, world!")
      "HTTP/1.1 200 OK\\r\\nContent-Type: text/plain\\r\\nContent-Length: 13\\r\\n\\r\\nHello, world!"

      iex> HttpResponse.new(404, headers: %{\"X-Custom\" => \"Value\"})
      "HTTP/1.1 404 Not Found\\r\\nX-Custom: Value\\r\\nContent-Type: text/plain\\r\\nContent-Length: 0\\r\\n\\r\\n"

  """
  def new(status_code, opts \\ []) do
    headers = Keyword.get(opts, :headers, %{})
    content_type = Keyword.get(opts, :content_type, "text/plain")
    body = Keyword.get(opts, :body, [])

    headers =
      case body do
        [] -> headers
        _ -> Map.put(headers, "Content-Type", content_type)
      end

    headers_str =
      headers
      |> Map.put("Content-Length", Integer.to_string(IO.iodata_length(body)))
      |> Map.to_list()
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\r\n")

    """
    HTTP/1.1 #{status_code} #{get_status_msg(status_code)}\r
    #{headers_str}\r
    \r
    #{body}\
    """
  end

  def get_status_msg(status_code) do
    case status_code do
      200 -> "OK"
      201 -> "Created"
      400 -> "Bad Request"
      404 -> "Not Found"
      405 -> "Method Not Allowed"
      408 -> "Request Timeout"
      500 -> "Internal Server Error"
    end
  end
end
