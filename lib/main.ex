defmodule Server do
  use Application

  def start(_type, _args) do
    directory = parse_directory(System.argv())

    if directory do
      Application.put_env(:codecrafters_http_server, :directory, directory)
    end

    children = [
      {Task, fn -> listen() end}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp parse_directory(argv) do
    case argv do
      ["--directory", dir | _] -> dir
      _ -> nil
    end
  end

  defp listen() do
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

  defp handle_client(socket) do
    timeout = 5000

    try do
      case HttpRequest.parse(socket, timeout) do
        {:ok, parsed_request} ->
          IO.puts("Received request...")
          IO.inspect(parsed_request, pretty: true)
          response = route_request(parsed_request)
          :gen_tcp.send(socket, response)

        {:error, :timeout} ->
          IO.puts("Request timed out during parsing.")
          :gen_tcp.send(socket, HttpResponse.new(408))

        {:error, :closed} ->
          IO.puts("Client disconnected before sending full request.")

        {:error, reason} ->
          IO.puts("Request parsing failed: #{reason}.")
          :gen_tcp.send(socket, HttpResponse.new(400))
      end
    rescue
      exception ->
        IO.puts("Stacktrace: #{Exception.format(:error, exception, __STACKTRACE__)}")
        :gen_tcp.send(socket, HttpResponse.new(500))
    after
      :gen_tcp.close(socket)
    end
  end

  defp route_request(%HttpRequest{
         method: method,
         target: target,
         headers: req_headers,
         body: body
       }) do
    route_segments = String.split(target, "/", trim: true)

    case {method, route_segments} do
      {"GET", []} ->
        HttpResponse.new(200)

      {"GET", ["echo", to_echo]} ->
        do_echo(req_headers, to_echo)

      {"GET", ["user-agent"]} ->
        req_headers
        |> Map.get("User-Agent", "")
        |> then(fn user_agent -> HttpResponse.new(200, body: user_agent) end)

      {"GET", ["files", file_name]} ->
        case Application.get_env(:codecrafters_http_server, :directory) do
          nil -> HttpResponse.new(500, body: "directory not set")
          directory -> serve_file(directory, file_name)
        end

      {"POST", ["files", file_name]} ->
        case Application.get_env(:codecrafters_http_server, :directory) do
          nil -> HttpResponse.new(500, body: "directory not set")
          directory -> write_file(directory, file_name, body)
        end

      {"GET", _} ->
        HttpResponse.new(404)

      {"PUT", _} ->
        HttpResponse.new(405)

      {"DELETE", _} ->
        HttpResponse.new(405)

      {_, _} ->
        HttpResponse.new(400)
    end
  end

  defp do_echo(req_headers, to_echo) do
    case determine_content_encoding(req_headers) do
      nil ->
        HttpResponse.new(200, body: to_echo)

      enc ->
        HttpResponse.new(200, headers: %{"Content-Encoding" => enc}, body: :zlib.gzip(to_echo))
    end
  end

  defp determine_content_encoding(req_headers) do
    req_headers
    |> Map.get("Accept-Encoding", "")
    |> String.split(", ")
    |> Enum.any?(&(&1 == "gzip"))
    |> case do
      true -> "gzip"
      _ -> nil
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

  defp write_file(directory, file_name, content) do
    path = Path.join(directory, file_name)

    case File.write(path, content) do
      :ok ->
        HttpResponse.new(201)

      {:error, reason} ->
        IO.puts("Failed to write file to #{path}: #{inspect(reason)}")
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
