defmodule HttpRequest do
  defstruct method: "", target: "", headers: %{}, body: ""

  def parse(request) do
    [before_body, body] = String.split(request, "\r\n\r\n", parts: 2)

    before_body_lines = String.split(before_body, "\r\n")

    request_line =
      before_body_lines
      |> List.first()
      |> String.split(" ", parts: 3)

    case request_line do
      [method, target, _http_version] ->
        headers =
          before_body_lines
          |> Enum.drop(1)
          |> Enum.map(fn line ->
            case String.split(line, ": ", parts: 2) do
              # Well-formed header
              [k, v] -> {k, v}
              # Missing value → Default to empty string
              [k] -> {k, ""}
            end
          end)
          |> Enum.into(%{})

        %HttpRequest{
          method: method,
          target: target,
          headers: headers,
          body: body
        }

      _ ->
        # Return an empty request for malformed inputs
        %HttpRequest{}
    end
  end
end

defmodule Server do
  use Application

  def start(_type, _args) do
    children = [
      {Task, fn -> Server.listen() end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def listen() do
    # Since the tester restarts your program quite often, setting SO_REUSEADDR
    # ensures that we don't run into 'Address already in use' errors
    {:ok, socket} = :gen_tcp.listen(4221, [:binary, active: false, reuseaddr: true])
    IO.puts("Listening...")
    accept_loop(socket)
  end

  defp accept_loop(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Task.start(fn -> handle_client(client) end)
    accept_loop(socket)
  end

  defp handle_client(client) do
    try do
      case :gen_tcp.recv(client, 0, 5000) do
        {:ok, request} ->
          IO.puts("Received request:\n#{request}")

          request = HttpRequest.parse(request)
          response = route_request(request)

          :gen_tcp.send(client, response)

        {:error, :timeout} ->
          IO.puts("Client timed out, closing connection.")
      end
    rescue
      exception ->
        IO.puts("Stacktrace: #{Exception.format(:error, exception, __STACKTRACE__)}")
    after
      :gen_tcp.close(client)
    end
  end

  defp route_request(%HttpRequest{method: method, target: target, headers: headers}) do
    route_segments = String.split(target, "/", trim: true)

    case {method, route_segments} do
      {"GET", []} ->
        build_response(200, "")

      {"GET", ["echo", to_echo]} ->
        build_response(200, to_echo)

      {"GET", ["user-agent"]} ->
        headers
        |> Map.get("User-Agent", "")
        |> then(&build_response(200, &1))

      {"GET", _} ->
        build_response(404, "")

      {_, _} ->
        build_response(405, "")
    end
  end

  defp build_response(status_code, body) do
    status_msg =
      case status_code do
        200 -> "OK"
        404 -> "Not Found"
        405 -> "Method Not Allowed"
      end

    """
    HTTP/1.1 #{status_code} #{status_msg}\r
    Content-Type: text/plain\r
    Content-Length: #{byte_size(body)}\r
    \r
    #{body}\
    """
  end
end

defmodule CLI do
  def main(_args) do
    # Start the Server application
    {:ok, _pid} = Application.ensure_all_started(:codecrafters_http_server)

    # Run forever
    Process.sleep(:infinity)
  end
end
