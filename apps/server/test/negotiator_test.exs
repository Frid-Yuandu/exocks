defmodule NegotiatorTest do
  alias Server.Negotiator
  use ExUnit.Case
  doctest Server.Negotiator

  setup_all do
    {:ok, ls} = :gen_tcp.listen(6716, [:binary, active: false, reuseaddr: true])
    on_exit(:stop_listener, fn -> :gen_tcp.close(ls) end)
    %{listen_sock: ls}
  end

  # test parse/2
  test "should parse user pass in all mode" do
    assert Negotiator.parse(%Negotiator{}, <<0, 2>>) ==
             %Negotiator{method: :user_pass, rule: :all}
  end

  test "should parse no auth in all mode" do
    assert Negotiator.parse(%Negotiator{}, <<0>>) ==
             %Negotiator{method: :no_auth, rule: :all}
  end

  test "should parse no acceptable in all mode" do
    assert Negotiator.parse(%Negotiator{}, <<1, 4, 9>>) ==
             %Negotiator{method: :no_acceptable, rule: :all}
  end

  test "should parse user pass in user pass mode" do
    assert Negotiator.parse(%Negotiator{rule: :user_pass}, <<1, 4, 2>>) ==
             %Negotiator{method: :user_pass, rule: :user_pass}
  end

  test "should parse no acceptable in user pass mode" do
    assert Negotiator.parse(%Negotiator{rule: :user_pass}, <<1, 4, 9>>) ==
             %Negotiator{method: :no_acceptable, rule: :user_pass}
  end

  # test negotiate/3
  test "should negotiate with no auth", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      %Negotiator{}
      |> Negotiator.parse(<<0, 1>>)
      |> Negotiator.negotiate(sock)

      :gen_tcp.close(sock)
    end)

    {:ok, server} = connect_to_server()
    assert {:ok, <<5, 0>>} = :gen_tcp.recv(server, 0)

    :gen_tcp.close(server)
  end

  test "should negotiate successfully with user pass", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      %Negotiator{}
      |> Negotiator.parse(<<0, 2>>)
      |> Negotiator.negotiate(sock)

      :gen_tcp.close(sock)
    end)

    {:ok, server} = connect_to_server()
    assert {:ok, <<5, 2>>} = :gen_tcp.recv(server, 0)
    :ok = :gen_tcp.send(server, <<1, 4, "user", 4, "pass">>)
    assert {:ok, <<1, 0>>} = :gen_tcp.recv(server, 0)

    :gen_tcp.close(server)
  end

  test "should negotiate failed with user pass", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      %Negotiator{}
      |> Negotiator.parse(<<0, 2>>)
      |> Negotiator.negotiate(sock)

      :gen_tcp.close(sock)
    end)

    {:ok, server} = connect_to_server()
    assert {:ok, <<5, 2>>} = :gen_tcp.recv(server, 0)
    :ok = :gen_tcp.send(server, <<1, 8, "username", 8, "password">>)
    assert {:ok, <<1, 1>>} = :gen_tcp.recv(server, 0)

    :gen_tcp.close(server)
  end

  test "should crush with invalid user pass", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      assert_raise FunctionClauseError, fn ->
        %Negotiator{}
        |> Negotiator.parse(<<0, 2>>)
        |> Negotiator.negotiate(sock)
      end

      :gen_tcp.close(sock)
    end)

    {:ok, server} = connect_to_server()
    assert {:ok, <<5, 2>>} = :gen_tcp.recv(server, 0)
    :ok = :gen_tcp.send(server, <<1, 8, "username", 7, "password">>)

    :gen_tcp.close(server)
  end

  test "should refuse negotiation with invalid user pass subversion", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      assert {:error, :invalid_sub_version} ==
               %Negotiator{}
               |> Negotiator.parse(<<0, 2>>)
               |> Negotiator.negotiate(sock)

      :gen_tcp.close(sock)
    end)

    {:ok, server} = connect_to_server()
    assert {:ok, <<5, 2>>} = :gen_tcp.recv(server, 0)
    :ok = :gen_tcp.send(server, <<0, 4, "user", 4, "pass">>)

    :gen_tcp.close(server)
  end

  test "should negotiate with no acceptable", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)

      %Negotiator{}
      |> Negotiator.parse(<<3, 1>>)
      |> Negotiator.negotiate(sock)

      :gen_tcp.close(sock)
    end)

    {:ok, server} = connect_to_server()
    assert {:ok, <<5, 0xFF>>} = :gen_tcp.recv(server, 0)

    :gen_tcp.close(server)
  end

  def connect_to_server() do
    :gen_tcp.connect({127, 0, 0, 1}, 6716, [:binary, active: false, reuseaddr: true])
  end
end
