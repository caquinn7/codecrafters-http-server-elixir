defmodule Server do
  use Application

  def start(_type, _args) do
    Supervisor.start_link([{Task, fn -> Server.listen() end}], strategy: :one_for_one)
  end

  def listen() do
    # You can use print statements as follows for debugging, they'll be visible when running tests.
    IO.puts("Logs from your program will appear here!")

    # Since the tester restarts your program quite often, setting SO_REUSEADDR
    # ensures that we don't run into 'Address already in use' errors
    {:ok, socket} = :gen_tcp.listen(4221, [:binary, active: false, reuseaddr: true])
    IO.puts("Listening...")

    {:ok, client} = :gen_tcp.accept(socket)
    IO.puts("Accepted connection...")

    {:ok, request} = :gen_tcp.recv(client, 0)
    IO.puts("Received request:\n#{request}")

    req_line =
      String.split(request, "\r\n")
      |> List.first
      |> String.split(" ")

    [_, req_target | _] = req_line

    resp = case req_target do
      "/" -> "HTTP/1.1 200 OK\r\n\r\n"
      _ -> "HTTP/1.1 404 Not Found\r\n\r\n"
    end

    :gen_tcp.send(client, resp)
    :gen_tcp.close(client)
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
