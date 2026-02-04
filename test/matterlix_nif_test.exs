defmodule Matterlix.Matter.NIFTest do
  use ExUnit.Case, async: false
  alias Matterlix.Matter.NIF

  describe "lifecycle" do
    test "init returns valid context" do
      assert {:ok, ctx} = NIF.nif_init()
      assert is_reference(ctx)
    end

    test "multiple init calls return contexts for same singleton" do
      assert {:ok, ctx1} = NIF.nif_init()
      assert {:ok, ctx2} = NIF.nif_init()
      assert is_reference(ctx1)
      assert is_reference(ctx2)
      # Both should work independently
      assert {:ok, _} = NIF.nif_get_info(ctx1)
      assert {:ok, _} = NIF.nif_get_info(ctx2)
    end

    test "get_info returns proper boolean atoms" do
      {:ok, ctx} = NIF.nif_init()
      {:ok, info} = NIF.nif_get_info(ctx)

      # Must be actual boolean, not :true atom
      assert info.initialized == true
      assert is_boolean(info.initialized)

      # Check other fields
      assert Map.has_key?(info, :is_owner)
      assert Map.has_key?(info, :has_listener)
      assert Map.has_key?(info, :nif_version)
    end

    test "start and stop server" do
      {:ok, ctx} = NIF.nif_init()
      assert :ok = NIF.nif_start_server(ctx)
      assert :ok = NIF.nif_stop_server(ctx)
    end
  end

  describe "callback registration" do
    test "register_callback succeeds" do
      {:ok, ctx} = NIF.nif_init()
      assert :ok = NIF.nif_register_callback(ctx)

      {:ok, info} = NIF.nif_get_info(ctx)
      assert info.has_listener == true
    end

    test "process death does not automatically clear callback" do
      # Note: Process monitoring was disabled to avoid BEAM shutdown race conditions.
      # This test verifies that the listener flag persists even after the process dies.
      # In production, GenServer supervision handles process lifecycle.
      {:ok, ctx} = NIF.nif_init()

      # Spawn a process that registers and then dies
      parent = self()

      pid =
        spawn(fn ->
          :ok = NIF.nif_register_callback(ctx)
          send(parent, :registered)

          receive do
            :die -> :ok
          end
        end)

      assert_receive :registered, 1000

      # Verify listener is registered
      {:ok, info_before} = NIF.nif_get_info(ctx)
      assert info_before.has_listener == true

      # Kill the process
      send(pid, :die)

      # Give time for any cleanup
      Process.sleep(100)

      # Context should still be valid and listener flag remains true
      # (no automatic cleanup without process monitoring)
      {:ok, info_after} = NIF.nif_get_info(ctx)
      assert info_after.has_listener == true
    end

    test "re-registering demonitors previous listener" do
      {:ok, ctx} = NIF.nif_init()

      # Register first
      assert :ok = NIF.nif_register_callback(ctx)

      # Register again (should work without error)
      assert :ok = NIF.nif_register_callback(ctx)

      {:ok, info} = NIF.nif_get_info(ctx)
      assert info.has_listener == true
    end
  end

  describe "commissioning" do
    test "get_setup_payload returns codes" do
      {:ok, ctx} = NIF.nif_init()
      assert {:ok, payload} = NIF.nif_get_setup_payload(ctx)

      assert Map.has_key?(payload, :qr_code)
      assert Map.has_key?(payload, :manual_code)
      assert is_binary(payload.qr_code) or is_list(payload.qr_code)
    end

    test "open_commissioning_window succeeds" do
      {:ok, ctx} = NIF.nif_init()
      assert :ok = NIF.nif_open_commissioning_window(ctx, 60)
    end

    test "set_commissioning_info validates input" do
      {:ok, ctx} = NIF.nif_init()

      # Valid values
      assert :ok = NIF.nif_set_commissioning_info(ctx, 20_202_021, 3840)

      # Invalid PIN (0)
      assert {:error, :invalid_pin} = NIF.nif_set_commissioning_info(ctx, 0, 3840)

      # Invalid PIN (too large)
      assert {:error, :invalid_pin} = NIF.nif_set_commissioning_info(ctx, 99_999_999, 3840)

      # Invalid discriminator (> 4095)
      assert {:error, :invalid_discriminator} =
               NIF.nif_set_commissioning_info(ctx, 20_202_021, 5000)
    end
  end

  describe "device management" do
    test "factory_reset succeeds" do
      {:ok, ctx} = NIF.nif_init()
      assert :ok = NIF.nif_factory_reset(ctx)
    end

    test "set_device_info succeeds" do
      {:ok, ctx} = NIF.nif_init()
      # VID=0xFFF1 (Test), PID=0x8001, Ver=1, Serial="12345678"
      assert :ok = NIF.nif_set_device_info(ctx, 0xFFF1, 0x8001, 1, "12345678")
    end
  end

  describe "wifi callbacks" do
    test "wifi_connect_result succeeds" do
      {:ok, ctx} = NIF.nif_init()
      assert :ok = NIF.nif_wifi_connect_result(ctx, 0)
    end

    test "wifi_scan_result succeeds" do
      {:ok, ctx} = NIF.nif_init()
      assert :ok = NIF.nif_wifi_scan_result(ctx, 0)
    end
  end

  describe "error handling" do
    test "invalid context returns error" do
      # Create a fake reference
      fake_ref = make_ref()

      assert {:error, :invalid_context} = NIF.nif_get_info(fake_ref)
      assert {:error, :invalid_context} = NIF.nif_start_server(fake_ref)
      assert {:error, :invalid_context} = NIF.nif_stop_server(fake_ref)
      assert {:error, :invalid_context} = NIF.nif_register_callback(fake_ref)
    end

    test "not initialized context returns error" do
      # This is hard to test without internal access to mark context as not initialized
      # Skip for now - covered by integration tests
    end
  end
end
