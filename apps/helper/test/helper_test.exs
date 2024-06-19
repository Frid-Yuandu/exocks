defmodule HelperTest do
  use ExUnit.Case
  doctest Helper

  test "greets the world" do
    assert Helper.hello() == :world
  end
end
