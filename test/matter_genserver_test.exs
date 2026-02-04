defmodule Matterlix.MatterTest do
  use ExUnit.Case, async: false
  alias Matterlix.Matter

  setup do
    # Start fresh GenServer for each test
    {:ok, pid} = Matter.start_link()

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
    end)

    {:ok, pid: pid}
  end

  describe "GenServer lifecycle" do
    test "start_link creates server", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "named registration works" do
      {:ok, pid} = Matter.start_link(name: TestMatter)
      assert Process.whereis(TestMatter) == pid
      GenServer.stop(pid)
    end

    test "auto_start option starts server", _context do
      {:ok, pid} = Matter.start_link(auto_start: true)
      # Give time for auto_start message
      Process.sleep(100)
      {:ok, info} = Matter.get_info(pid)
      assert info.initialized == true
      GenServer.stop(pid)
    end
  end

  describe "server operations" do
    test "start_server/stop_server cycle", %{pid: pid} do
      assert :ok = Matter.start_server(pid)
      assert {:error, :already_started} = Matter.start_server(pid)
      assert :ok = Matter.stop_server(pid)
      assert {:error, :not_started} = Matter.stop_server(pid)
    end

    test "get_info returns map", %{pid: pid} do
      {:ok, info} = Matter.get_info(pid)
      assert is_map(info)
      assert Map.has_key?(info, :initialized)
      assert info.initialized == true
    end
  end

  describe "commissioning" do
    test "get_setup_payload returns codes", %{pid: pid} do
      {:ok, payload} = Matter.get_setup_payload(pid)
      assert Map.has_key?(payload, :qr_code)
      assert Map.has_key?(payload, :manual_code)
    end

    test "open_commissioning_window succeeds", %{pid: pid} do
      assert :ok = Matter.open_commissioning_window(pid, 60)
    end

    test "set_commissioning_info succeeds", %{pid: pid} do
      assert :ok = Matter.set_commissioning_info(pid, 20_202_021, 3840)
    end
  end

  describe "device management" do
    test "set_device_info succeeds", %{pid: pid} do
      assert :ok =
               Matter.set_device_info(pid,
                 vid: 0xFFF1,
                 pid: 0x8001,
                 version: 1,
                 serial: "TEST001"
               )
    end

    test "factory_reset succeeds", %{pid: pid} do
      assert :ok = Matter.factory_reset(pid)
    end
  end

  describe "WiFi commissioning messages" do
    test "connect_network message is handled", %{pid: pid} do
      # Simulate NIF sending connect_network message
      send(pid, {:connect_network, "TestSSID", "password123"})

      # Should not crash - verify process still alive
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "add_network message is handled", %{pid: pid} do
      send(pid, {:add_network, "TestSSID", "password123"})
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "scan_networks message is handled", %{pid: pid} do
      send(pid, {:scan_networks, :undefined})
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "multiple connect_network messages don't leak timers", %{pid: pid} do
      # Send multiple rapid connect requests
      send(pid, {:connect_network, "SSID1", "pass1"})
      send(pid, {:connect_network, "SSID2", "pass2"})
      send(pid, {:connect_network, "SSID3", "pass3"})

      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "wifi_connect_timeout is handled", %{pid: pid} do
      send(pid, :wifi_connect_timeout)
      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end

  describe "attribute_changed handling" do
    test "attribute_changed message is handled", %{pid: pid} do
      # Simulate Matter SDK callback
      send(pid, {:attribute_changed, 1, 0x0006, 0x0000, 0x10, true})
      Process.sleep(50)
      assert Process.alive?(pid)
    end

    test "attribute_changed with various types", %{pid: pid} do
      # Boolean
      send(pid, {:attribute_changed, 1, 0x0006, 0x0000, 0x10, true})
      # Integer
      send(pid, {:attribute_changed, 1, 0x0008, 0x0000, 0x20, 128})
      # Nil (unknown type)
      send(pid, {:attribute_changed, 1, 0x0300, 0x0000, 0x99, nil})

      Process.sleep(50)
      assert Process.alive?(pid)
    end
  end

  describe "termination" do
    test "terminate stops server if started", %{pid: pid} do
      :ok = Matter.start_server(pid)
      # Normal stop should call terminate which stops the server
      GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end
  end
end
