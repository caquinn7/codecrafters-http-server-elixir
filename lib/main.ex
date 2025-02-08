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

defmodule HttpResponse do
  defstruct status_code: "", headers: %{}, body: ""

  def new(status_code, opts \\ []) do
    headers = Keyword.get(opts, :headers, %{})
    content_type = Keyword.get(opts, :content_type, "text/plain")
    body = Keyword.get(opts, :body, "")

    status_msg =
      case status_code do
        200 -> "OK"
        404 -> "Not Found"
        405 -> "Method Not Allowed"
        500 -> "Internal Server Error"
      end

    headers_str =
      headers
      |> Map.put("Content-Type", content_type)
      |> Map.put("Content-Length", Integer.to_string(byte_size(body)))
      |> Map.to_list()
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\r\n")

    """
    HTTP/1.1 #{status_code} #{status_msg}\r
    #{headers_str}\r
    \r
    #{body}\
    """
  end
end

defmodule Server do
  use Application

  def start(_type, _args) do
    directory = parse_directory(System.argv())

    if directory do
      Application.put_env(:codecrafters_http_server, :directory, directory)
    end

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

  defp parse_directory(argv) do
    case argv do
      ["--directory", dir | _] -> dir
      _ -> nil
    end
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
        HttpResponse.new(200)

      {"GET", ["echo", to_echo]} ->
        HttpResponse.new(200, body: to_echo)

      {"GET", ["user-agent"]} ->
        headers
        |> Map.get("User-Agent", "")
        |> then(fn user_agent -> HttpResponse.new(200, body: user_agent) end)

      {"GET", ["files", file_name]} ->
        case Application.get_env(:codecrafters_http_server, :directory) do
          nil -> HttpResponse.new(500, body: "directory not set")
          directory -> serve_file(directory, file_name)
        end

      {"GET", _} ->
        HttpResponse.new(404)

      {_, _} ->
        HttpResponse.new(405)
    end
  end

  defp serve_file(directory, file_name) do
    path = Path.join(directory, file_name)

    case File.read(path) do
      {:ok, contents} ->
        HttpResponse.new(200,
          content_type: "application/octet-stream",
          body: contents
        )

      {:error, :enoent} ->
        HttpResponse.new(404)

      {:error, reason} ->
        IO.puts("Failed to read file at #{path}: #{inspect(reason)}")
        HttpResponse.new(500)
    end
  end
end

defmodule Cli do
  def main(_args) do
    # Start the Server application
    {:ok, _pid} = Application.ensure_all_started(:codecrafters_http_server)
    # Run forever
    Process.sleep(:infinity)
  end
end
