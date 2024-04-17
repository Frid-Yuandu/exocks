defmodule NegotiatorTest do
  use ExUnit.Case
  doctest Server
  alias Server.Negotiator

  setup_all do
    {:ok, ls} = :gen_tcp.listen(6716, [:binary, active: false, reuseaddr: true])
    on_exit(:stop_listener, fn -> :gen_tcp.close(ls) end)
    %{listen_sock: ls}
  end

  # test new/1
  test "should new negotiator successfully" do
    assert %Negotiator{version: 5, methods: [0, 2], rule: :all} = Negotiator.new()
  end

  test "should new negotiator failed" do
    assert_raise ArgumentError,
                 "invalid rule: invalid_rule, available rules: all, user_pass",
                 fn -> Negotiator.new(:invalid_rule) end
  end

  # test select/2
  test "should select user pass in all mode" do
    assert Negotiator.select([0, 2], <<0, 2>>) == :user_pass
  end

  test "should select no auth in all mode" do
    assert Negotiator.select([0, 2], <<0>>) == :no_auth
  end

  test "should select no acceptable in all mode" do
    assert Negotiator.select([0, 2], <<1, 3, 4>>) == :no_acceptable
  end

  test "should select user pass in user pass mode" do
    assert Negotiator.select([2], <<0, 2>>) == :user_pass
  end

  test "should select no acceptable in user pass mode" do
    assert Negotiator.select([2], <<0>>) == :no_acceptable
  end

  # test negotiate/3
  test "should negotiate with no auth", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)
      on_exit(fn -> :gen_tcp.close(sock) end)

      Negotiator.new()
      |> Negotiator.negotiate(sock, <<0, 1>>)
    end)

    {:ok, server} =
      :gen_tcp.connect({127, 0, 0, 1}, 6716, [:binary, active: false, reuseaddr: true])

    on_exit(fn -> :gen_tcp.close(server) end)

    assert {:ok, <<5, 0>>} = :gen_tcp.recv(server, 0)
  end

  test "should negotiate with no acceptable", %{listen_sock: ls} do
    Task.start(fn ->
      {:ok, sock} = :gen_tcp.accept(ls)
      on_exit(fn -> :gen_tcp.close(sock) end)

      Negotiator.new()
      |> Negotiator.negotiate(sock, <<3, 1>>)
    end)

    {:ok, server} =
      :gen_tcp.connect({127, 0, 0, 1}, 6716, [:binary, active: false, reuseaddr: true])

    on_exit(fn -> :gen_tcp.close(server) end)

    assert {:ok, <<5, 255>>} = :gen_tcp.recv(server, 0)
  end
end
