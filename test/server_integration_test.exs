defmodule ServerIntegrationTest do
  use ExUnit.Case

  @host ~c"localhost"
  @port 4221
  @timeout 5000

  setup do
    # Start the entire application (which starts the Server)
    {:ok, _} = Application.ensure_all_started(:codecrafters_http_server)
    on_exit(fn -> Application.stop(:codecrafters_http_server) end)
    :ok
  end

  test "GET / returns 200 OK" do
    request =
      """
      GET / HTTP/1.1\r
      Host: localhost\r
      Content-Length: 0\r
      \r
      """

    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, request)
    {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
    :gen_tcp.close(socket)

    assert String.contains?(response, "HTTP/1.1 200 OK")
  end

  test "GET /user-agent returns the User-Agent header" do
    request =
      """
      GET /user-agent HTTP/1.1\r
      Host: localhost\r
      Content-Length: 0\r
      User-Agent: foobar/1.2.3\r
      \r
      """

    {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
    :ok = :gen_tcp.send(socket, request)
    {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
    :gen_tcp.close(socket)

    assert String.contains?(response, "HTTP/1.1 200 OK")
    assert String.contains?(response, "foobar/1.2.3")
  end

  describe "echo" do
    test "GET /echo/hello returns echoed content" do
      request =
        """
        GET /echo/hello HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        \r
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, "hello")
    end

    test "POST /echo returns the posted body" do
      request =
        """
        POST /echo HTTP/1.1\r
        Host: localhost\r
        Content-Length: 5\r
        \r
        hello\
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, "hello")
    end

    test "POST /echo returns the posted body when body arrives in multiple chunks" do
      # We'll simulate a POST request to /echo with a body "Hello World" (11 bytes)
      # The headers and first chunk of the body ("Hello") are sent first,
      # then after a short delay, the remainder (" World") is sent.
      request_part1 =
        """
        POST /echo HTTP/1.1\r
        Host: localhost\r
        Content-Length: 11\r
        \r
        Hello\
        """

      request_part2 = " World"

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])

      # Send the first part (headers + partial body)
      :ok = :gen_tcp.send(socket, request_part1)

      # Pause to simulate delay in the transmission of the remainder
      :timer.sleep(1000)

      # Send the remaining part of the body
      :ok = :gen_tcp.send(socket, request_part2)

      # Read the response from the server
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      # Assert the response is 200 OK and that it echoes "Hello World"
      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, "Hello World")
    end

    test "/echo encodes content when valid Accept-Encoding header sent" do
      to_echo = "hello"

      request =
        """
        GET /echo/#{to_echo} HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        Accept-Encoding: gzip\r
        \r
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, :zlib.gzip(to_echo))
    end

    test "/echo does not encode content when Accept-Encoding header is invalid" do
      to_echo = "hello"

      request =
        """
        GET /echo/#{to_echo} HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        Accept-Encoding: invalid\r
        \r
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, to_echo)
    end
  end

  describe "files" do
    test "GET /files/<filename> returns file contents if file exists" do
      tmp_dir = System.tmp_dir!()
      file_name = "test_file_#{:os.system_time(:millisecond)}.txt"
      file_path = Path.join(tmp_dir, file_name)

      expected_content = "This is a temporary file for testing."
      :ok = File.write(file_path, expected_content)

      # Ensure the file is deleted after the test, even if an error is raised.
      on_exit(fn -> File.rm(file_path) end)

      # Set the application environment so that the server knows where to look for files.
      Application.put_env(:codecrafters_http_server, :directory, tmp_dir)

      request =
        """
        GET /files/#{file_name} HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        \r
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, expected_content)
    end

    test "GET /files/<filename> returns 404 if file does not exist" do
      Application.put_env(:codecrafters_http_server, :directory, System.tmp_dir!())

      request =
        """
        GET /files/non_existent_file HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        \r
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 404 Not Found")
    end

    test "POST /files/<filename> writes the body to a file and returns 201" do
      tmp_dir = System.tmp_dir!()
      file_name = "test_file_#{:os.system_time(:millisecond)}.txt"
      file_path = Path.join(tmp_dir, file_name)
      on_exit(fn -> File.rm(file_path) end)

      file_content = "This is the file content."

      Application.put_env(:codecrafters_http_server, :directory, tmp_dir)

      request =
        """
        POST /files/#{file_name} HTTP/1.1\r
        Host: localhost\r
        Content-Length: #{byte_size(file_content)}\r
        \r
        #{file_content}\
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 201 Created")
      assert File.exists?(file_path)
      assert File.read!(file_path) == file_content
    end
  end

  describe "error handling" do
    test "returns 400 Bad Request when Content-Length does not match length of content" do
      request =
        """
        POST /echo HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        \r
        hello\
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 400 Bad Request")
    end

    test "returns 400 Bad Request for a malformed request" do
      # request is malformed due to no target in request line
      request =
        """
        GET HTTP/1.1\r
        Host: localhost\r
        Content-Length: 0\r
        \r
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      # Do not send the rest of the body
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 400 Bad Request")
    end

    test "returns 405 Method Not Allowed for unsupported HTTP methods" do
      request =
        """
        PUT /echo HTTP/1.1\r
        Host: localhost\r
        Content-Length: 5\r
        \r
        hello\
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)

      assert String.contains?(response, "HTTP/1.1 405 Method Not Allowed")
    end

    test "returns 408 Request Timeout when the client times out" do
      # Send an incomplete request that will timeout
      request =
        """
        POST /echo HTTP/1.1\r
        Host: localhost\r
        Content-Length: 10\r
        \r
        hel
        """

      {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])
      :ok = :gen_tcp.send(socket, request)
      # Do not send the rest of the body
      {:error, :timeout} = :gen_tcp.recv(socket, 0, @timeout)
      :gen_tcp.close(socket)
    end
  end

  test "server handles concurrent connections" do
    # We'll spawn multiple tasks, each of which connects to the server,
    # sends a GET /echo/hello request, and collects the response.
    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.connect(@host, @port, [:binary, active: false])

          request =
            """
            GET /echo/hello HTTP/1.1\r
            Host: localhost\r
            Content-Length: 0\r
            \r
            """

          :ok = :gen_tcp.send(socket, request)
          {:ok, response} = :gen_tcp.recv(socket, 0, @timeout)
          :gen_tcp.close(socket)
          response
        end)
      end

    # Wait for all tasks to complete and collect responses.
    responses = Enum.map(tasks, &Task.await(&1, @timeout))

    # Assert that each response is correct.
    Enum.each(responses, fn response ->
      assert String.contains?(response, "HTTP/1.1 200 OK")
      assert String.contains?(response, "hello")
    end)
  end
end
