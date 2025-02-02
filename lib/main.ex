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
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, request} = :gen_tcp.recv(client, 0)
    IO.puts("Received request:\n#{request}")

    {method, target, headers, _body} = destruct_request(request)
    route_segments = String.split(target, "/", trim: true)

    resp =
      case {method, route_segments} do
        {"GET", []} ->
          build_response(200, "")

        {"GET", ["echo", to_echo]} ->
          build_response(200, to_echo)

        {"GET", ["user-agent"]} ->
          headers
          |> Map.get("User-Agent", "")
          |> then(fn x -> build_response(200, x) end)

        {"GET", _} ->
          build_response(404, "")

        {_, _} ->
          build_response(405, "")
      end

    :gen_tcp.send(client, resp)
    :gen_tcp.close(client)
  end

  defp destruct_request(request) do
    [before_body, body] = String.split(request, "\r\n\r\n")

    before_body_lines = String.split(before_body, "\r\n")

    [method, target, _http_version] =
      before_body_lines
      |> List.first()
      |> String.split(" ")

    headers =
      before_body_lines
      |> Enum.drop(1)
      |> Enum.map(fn line ->
        line
        |> String.split(": ", trim: true)
        |> case do
          [k, v] -> {k, v}
        end
      end)
      |> Enum.into(%{})

    {method, target, headers, body}
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
