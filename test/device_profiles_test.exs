defmodule Matterlix.DeviceProfilesTest do
  use ExUnit.Case, async: true

  alias Matterlix.DeviceProfiles

  describe "get!/1" do
    test "returns profile for valid name" do
      profile = DeviceProfiles.get!(:light)
      assert profile.gn_root == "examples/lighting-app/linux"
      assert profile.executable == "chip-lighting-app"
      assert is_binary(profile.description)
    end

    test "raises for unknown profile" do
      assert_raise ArgumentError, ~r/Unknown device profile: :nonexistent/, fn ->
        DeviceProfiles.get!(:nonexistent)
      end
    end
  end

  describe "get/1" do
    test "returns {:ok, profile} for valid name" do
      assert {:ok, profile} = DeviceProfiles.get(:lock)
      assert profile.gn_root == "examples/lock-app/linux"
      assert profile.executable == "chip-lock-app"
    end

    test "returns :error for unknown profile" do
      assert :error = DeviceProfiles.get(:nonexistent)
    end
  end

  describe "list/0" do
    test "returns all profiles" do
      profiles = DeviceProfiles.list()
      assert is_map(profiles)
      assert Map.has_key?(profiles, :light)
      assert Map.has_key?(profiles, :contact_sensor)
      assert Map.has_key?(profiles, :lock)
      assert Map.has_key?(profiles, :thermostat)
      assert Map.has_key?(profiles, :air_quality_sensor)
      assert Map.has_key?(profiles, :all_clusters)
      assert map_size(profiles) == 6
    end

    test "all profiles have required keys" do
      for {_name, profile} <- DeviceProfiles.list() do
        assert is_binary(profile.gn_root)
        assert is_binary(profile.executable)
        assert is_binary(profile.description)
      end
    end
  end

  describe "valid?/1" do
    test "returns true for known profiles" do
      assert DeviceProfiles.valid?(:light)
      assert DeviceProfiles.valid?(:contact_sensor)
      assert DeviceProfiles.valid?(:lock)
      assert DeviceProfiles.valid?(:thermostat)
      assert DeviceProfiles.valid?(:air_quality_sensor)
      assert DeviceProfiles.valid?(:all_clusters)
    end

    test "returns false for unknown profiles" do
      refute DeviceProfiles.valid?(:nonexistent)
      refute DeviceProfiles.valid?(:foo)
    end
  end
end
