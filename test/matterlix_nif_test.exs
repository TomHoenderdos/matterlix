defmodule Matterlix.Matter.NIFTest do
  use ExUnit.Case
  alias Matterlix.Matter.NIF

  test "lifecycle and basic info" do
    assert {:ok, ctx} = NIF.nif_init()
    assert {:ok, info} = NIF.nif_get_info(ctx)
    assert info.initialized == :true
    assert :ok = NIF.nif_start_server(ctx)
    assert :ok = NIF.nif_stop_server(ctx)
  end

  test "commissioning functions" do
    {:ok, ctx} = NIF.nif_init()
    
    # Test Setup Payload
    assert {:ok, payload} = NIF.nif_get_setup_payload(ctx)
    assert Map.has_key?(payload, :qr_code)
    assert Map.has_key?(payload, :manual_code)
    
    # Test Open Window
    assert :ok = NIF.nif_open_commissioning_window(ctx, 60)
  end

  test "device management" do
    {:ok, ctx} = NIF.nif_init()
    
    # Factory Reset
    assert :ok = NIF.nif_factory_reset(ctx)
    
    # Set Device Info
    # VID=0xFFF1 (Test), PID=0x8001, Ver=1, Serial="12345678"
    assert :ok = NIF.nif_set_device_info(ctx, 0xFFF1, 0x8001, 1, "12345678")
  end

  test "callback registration" do
    {:ok, ctx} = NIF.nif_init()
    assert :ok = NIF.nif_register_callback(ctx)
  end

  test "wifi callback stub" do
    {:ok, ctx} = NIF.nif_init()
    assert :ok = NIF.nif_wifi_connect_result(ctx, 0)
  end
end
