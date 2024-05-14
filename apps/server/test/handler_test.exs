defmodule HandlerTest do
  use ExUnit.Case
  doctest Server.Handler

  @ipv4 1
  @ipv6 4
  @domain 3

  # test extract_addr_port/1
  test "should extract ipv4 address port" do
    ipv4_binary = <<@ipv4, 127, 0, 0, 1, 80::16>>
    wanted = {{127, 0, 0, 1}, 80}

    assert wanted == Server.Handler.extract_addr_port(ipv4_binary)
  end

  test "should extract ipv6 address port" do
    ipv6_binary = <<@ipv6, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 1::16, 4321::16>>
    wanted = {{0, 0, 0, 0, 0, 0, 0, 1}, 4321}

    assert wanted == Server.Handler.extract_addr_port(ipv6_binary)
  end

  test "should extract domain address port" do
    domain_binary = <<@domain, 9, "localhost", 80::16>>
    wanted = {~c"localhost", 80}

    assert wanted == Server.Handler.extract_addr_port(domain_binary)
  end

  test "should not extract invalid ipv4 address" do
    invalid_ipv4_binary = <<@ipv4, 127, 0, 0, 1, 80::16, 4321::16>>

    assert_raise FunctionClauseError, fn ->
      Server.Handler.extract_addr_port(invalid_ipv4_binary)
    end
  end

  test "should not extract invalid ipv6 address" do
    invalid_ipv6_binary = <<@ipv6, 0::16, 0::16, 0::16, 1::16, 0xFF83::16, 4321::16>>

    assert_raise FunctionClauseError, fn ->
      Server.Handler.extract_addr_port(invalid_ipv6_binary)
    end
  end

  test "should not extract invalid domain" do
    invalid_domain_binary = <<@domain, 1, "www.google.com", 443::16>>

    assert_raise FunctionClauseError, fn ->
      Server.Handler.extract_addr_port(invalid_domain_binary)
    end
  end

  test "should not extract unexpected address type" do
    invalid_address_type = 0xFF
    invalid_binary = <<invalid_address_type, 127, 0, 0, 1, 80::16>>

    assert_raise FunctionClauseError, fn -> Server.Handler.extract_addr_port(invalid_binary) end
  end

  # test to_ip_address/1
  test "should convert ipv4" do
    ipv4_binary = <<127, 0, 0, 1>>
    wanted = {127, 0, 0, 1}

    assert wanted == Server.Handler.to_ip_address(ipv4_binary)
  end

  test "should convert ipv6" do
    ipv6_binary = <<0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 0::16, 1::16>>
    wanted = {0, 0, 0, 0, 0, 0, 0, 1}

    assert wanted == Server.Handler.to_ip_address(ipv6_binary)
  end

  test "should not convert invalid address" do
    invalid_binary = <<0::16, 0::16, 0::16, 0::16, 0::16, 1::16>>

    assert_raise FunctionClauseError, fn -> Server.Handler.to_ip_address(invalid_binary) end
  end
end
