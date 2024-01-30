defmodule ExocksTest do
  use ExUnit.Case
  doctest Exocks

  test "greets the world" do
    assert Exocks.hello() == :world
  end
end
