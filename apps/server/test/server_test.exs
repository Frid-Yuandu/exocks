defmodule ServerTest do
  use ExUnit.Case
  import TestHelper, only: [connect_to_exocks: 0, send_recv: 2]
  doctest Server

  @server_port Application.compile_env(:server, :local_port)

  @no_auth 0x00
  @userpass 0x02
  @no_acceptable 0xFF
  @user_pass_version 0x01

  @socks_version 0x05
  @tcp 0x01
  @ipv4 0x01
  # @domain 0x03
  # @ipv6 0x04
  @req_succeeded 0x00

  setup_all do
    {:ok, _} = Server.start_link([])
    on_exit(:stop_listener, fn -> Server.stop() end)

    {:ok, ls} = :gen_tcp.listen(14579, [:binary, active: false, reuseaddr: true])
    on_exit(:stop_dest_server, fn -> :gen_tcp.close(ls) end)

    %{listen_sock: ls}
  end

  test "should proxy with no auth, ipv4, tcp connect", %{listen_sock: ls} do
    address_type = @ipv4
    command = @tcp
    uri = <<127, 0, 0, 1, 14579::16>>

    neg_sent = <<@socks_version, 1, @no_auth>>
    neg_wanted = <<@socks_version, @no_auth>>
    req_sent = <<@socks_version, command, 0, address_type, uri::binary>>
    req_wanted = <<@socks_version, @req_succeeded, 0, @ipv4, 127, 0, 0, 1, @server_port::16>>
    msg_sent = "ping"
    msg_wanted = "pong"

    Task.start_link(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      {:ok, ^msg_sent} = :gen_tcp.recv(sock, 0)
      :ok = :gen_tcp.send(sock, "pong")

      :gen_tcp.close(sock)
    end)

    connect_to_exocks()
    |> send_recv(send: neg_sent, wanted: {:ok, neg_wanted})
    |> send_recv(send: req_sent, wanted: {:ok, req_wanted})
    |> send_recv(send: msg_sent, wanted: {:ok, msg_wanted})
    |> :gen_tcp.close()
  end

  test "should proxy with userpass, ipv4, tcp connect", %{listen_sock: ls} do
    address_type = @ipv4
    command = @tcp
    uri = <<127, 0, 0, 1, 14579::16>>

    neg_sent = <<@socks_version, 1, @userpass>>
    neg_wanted = <<@socks_version, @userpass>>
    userpass_sent = <<@user_pass_version, 4, "user", 4, "pass">>
    userpass_wanted = <<@user_pass_version, 0>>
    req_sent = <<@socks_version, command, 0, address_type, uri::binary>>
    req_wanted = <<@socks_version, @req_succeeded, 0, @ipv4, 127, 0, 0, 1, @server_port::16>>
    msg_sent = "ping"
    msg_wanted = "pong"

    Task.start_link(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      {:ok, ^msg_sent} = :gen_tcp.recv(sock, 0)
      :ok = :gen_tcp.send(sock, "pong")

      :gen_tcp.close(sock)
    end)

    connect_to_exocks()
    |> send_recv(send: neg_sent, wanted: {:ok, neg_wanted})
    |> send_recv(send: userpass_sent, wanted: {:ok, userpass_wanted})
    |> send_recv(send: req_sent, wanted: {:ok, req_wanted})
    |> send_recv(send: msg_sent, wanted: {:ok, msg_wanted})
    |> :gen_tcp.close()
  end

  test "should not proxy with wrong userpass, ipv4, tcp connect", %{} do
    neg_sent = <<@socks_version, 1, @userpass>>
    neg_wanted = <<@socks_version, @userpass>>
    userpass_sent = <<@user_pass_version, 8, "username", 8, "password">>
    userpass_wanted = <<@user_pass_version, 1>>

    connect_to_exocks()
    |> send_recv(send: neg_sent, wanted: {:ok, neg_wanted})
    |> send_recv(send: userpass_sent, wanted: {:ok, userpass_wanted})
    |> :gen_tcp.close()
  end

  test "should proxy with no acceptable", %{} do
    neg_sent = <<@socks_version, 2, 1, 3>>
    neg_wanted = <<@socks_version, @no_acceptable>>

    connect_to_exocks()
    |> send_recv(send: neg_sent, wanted: {:ok, neg_wanted})
    |> :gen_tcp.close()
  end
end
