defmodule MatterlixTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Matterlix.Matter.start_link(name: Matterlix.Matter)

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
    end)

    {:ok, pid: pid}
  end

  test "update_attribute/4 delegates to Matter GenServer" do
    assert :ok = Matterlix.update_attribute(1, 0x0006, 0x0000, true)
  end

  test "get_attribute/3 delegates to Matter GenServer" do
    {:ok, _value} = Matterlix.get_attribute(1, 0x0006, 0x0000)
  end
end
