defmodule MatterlixTest do
  use ExUnit.Case
  doctest Matterlix

  test "greets the world" do
    assert Matterlix.hello() == :world
  end
end
