defmodule HttpResponseTest do
  use ExUnit.Case
  alias HttpResponse

  test "new builds a valid 200 OK response" do
    body = "Hello, world!"
    result = HttpResponse.new(200, body: body)

    expected =
      """
      HTTP/1.1 200 OK\r
      Content-Length: #{byte_size(body)}\r
      Content-Type: text/plain\r
      \r
      #{body}\
      """

    assert String.equivalent?(expected, result)
  end

  test "new builds a valid response with no body" do
    result = HttpResponse.new(200)

    expected =
      """
      HTTP/1.1 200 OK\r
      Content-Length: 0\r
      \r
      """

    assert String.equivalent?(expected, result)
  end

  test "new uses Content-Type given by caller" do
    content_type = "application/json"
    body = "1"
    result = HttpResponse.new(200, content_type: content_type, body: body)

    expected =
      """
      HTTP/1.1 200 OK\r
      Content-Length: #{byte_size(body)}\r
      Content-Type: #{content_type}\r
      \r
      #{body}\
      """

    assert String.equivalent?(expected, result)
  end

  test "new gets Content-Length from body" do
    headers = %{"Content-Length" => "0"}
    body = "Hello, world!"
    result = HttpResponse.new(200, headers: headers, body: body)

    expected =
      """
      HTTP/1.1 200 OK\r
      Content-Length: #{byte_size(body)}\r
      Content-Type: text/plain\r
      \r
      #{body}\
      """

    assert String.equivalent?(expected, result)
  end

  test "new uses headers given by caller" do
    headers = %{
      "MyHeader1" => "abc",
      "MyHeader2" => "def"
    }

    result = HttpResponse.new(200, headers: headers)

    expected =
      """
      HTTP/1.1 200 OK\r
      Content-Length: 0\r
      MyHeader1: abc\r
      MyHeader2: def\r
      \r
      """

    assert String.equivalent?(expected, result)
  end

  test "get_status_msg returns correct message for each status code" do
    test_cases = [
      {200, "OK"},
      {201, "Created"},
      {400, "Bad Request"},
      {404, "Not Found"},
      {405, "Method Not Allowed"},
      {408, "Request Timeout"},
      {500, "Internal Server Error"}
    ]

    Enum.each(test_cases, fn {status, expected_msg} ->
      assert HttpResponse.get_status_msg(status) == expected_msg
    end)
  end
end
