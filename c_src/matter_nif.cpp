/**
 * Matter NIF - Native Implemented Functions for Matter SDK integration
 *
 * This NIF provides Elixir bindings for the Matter (formerly CHIP) SDK,
 * enabling Nerves devices to participate in Matter smart home networks.
 */

#include <erl_nif.h>
#include <cstring>
#include <string>

// Forward declarations for Matter SDK integration
#if MATTER_SDK_ENABLED
#include <app/server/Server.h>
#include <platform/CHIPDeviceLayer.h>
#include <app/util/attribute-storage.h>
#include <app-common/zap-generated/attribute-type.h>
#include <app/server/CommissioningWindowManager.h>
#include <setup_payload/QRCodeSetupPayloadGenerator.h>
#include <setup_payload/OnboardingCodesUtil.h>
#include <platform/ConfigurationManager.h>
#include <platform/NetworkCommissioning.h>
#endif

// Helper macros for creating Erlang terms
#define ATOM(env, name) enif_make_atom(env, name)
#define OK(env) ATOM(env, "ok")
#define ERROR(env) ATOM(env, "error")
#define OK_TUPLE(env, term) enif_make_tuple2(env, OK(env), term)
#define ERROR_TUPLE(env, reason) enif_make_tuple2(env, ERROR(env), ATOM(env, reason))

// Resource type for Matter context (will hold Matter SDK state)
static ErlNifResourceType* MATTER_CONTEXT_RESOURCE = nullptr;

#if MATTER_SDK_ENABLED
class NervesWiFiDriver : public chip::DeviceLayer::NetworkCommissioning::WiFiDriver {
public:
    // Storage for credentials between AddOrUpdateNetwork and ConnectNetwork
    static constexpr size_t kMaxSSIDLength = 32;
    static constexpr size_t kMaxCredentialsLength = 64;
    uint8_t mSavedSSID[kMaxSSIDLength];
    size_t mSavedSSIDLength = 0;
    uint8_t mSavedCredentials[kMaxCredentialsLength];
    size_t mSavedCredentialsLength = 0;
    bool mHasNetwork = false;

    void Init(chip::DeviceLayer::NetworkCommissioning::BaseDriver::NetworkStatusChangeCallback * statusChangeCallback) override { }
    void Shutdown() override { }
    uint8_t GetMaxNetworks() override { return 1; }
    uint8_t GetScanNetworkTimeoutSeconds() override { return 10; }
    uint8_t GetConnectNetworkTimeoutSeconds() override { return 20; }
    CHIP_ERROR CommitConfiguration() override { return CHIP_NO_ERROR; }
    CHIP_ERROR RevertConfiguration() override { return CHIP_NO_ERROR; }

    CHIP_ERROR ScanNetworks(chip::ByteSpan ssid, WiFiDriver::ScanCallback * callback) override;
    CHIP_ERROR ConnectNetwork(chip::ByteSpan ssid, WiFiDriver::ConnectCallback * callback) override;

    size_t GetNetworksSize() override { return mHasNetwork ? 1 : 0; }
    const chip::DeviceLayer::NetworkCommissioning::Network * GetNetworks() override { return nullptr; }

    CHIP_ERROR AddOrUpdateNetwork(chip::ByteSpan ssid, chip::ByteSpan credentials,
                                  chip::MutableCharSpan & outDebugText, uint8_t & outNetworkIndex) override {
        // Store credentials for later use in ConnectNetwork
        mSavedSSIDLength = std::min(ssid.size(), kMaxSSIDLength);
        memcpy(mSavedSSID, ssid.data(), mSavedSSIDLength);

        mSavedCredentialsLength = std::min(credentials.size(), kMaxCredentialsLength);
        memcpy(mSavedCredentials, credentials.data(), mSavedCredentialsLength);
        mHasNetwork = true;

        // Notify Elixir about the new network
        if (g_matter_context && g_matter_context->has_listener) {
            ErlNifEnv* msg_env = enif_alloc_env();
            if (msg_env) {
                ERL_NIF_TERM ssid_term, cred_term;
                unsigned char* buf;

                buf = enif_make_new_binary(msg_env, ssid.size(), &ssid_term);
                memcpy(buf, ssid.data(), ssid.size());

                buf = enif_make_new_binary(msg_env, credentials.size(), &cred_term);
                memcpy(buf, credentials.data(), credentials.size());

                ERL_NIF_TERM msg = enif_make_tuple3(msg_env, ATOM(msg_env, "add_network"), ssid_term, cred_term);
                enif_send(NULL, &g_matter_context->listener_pid, msg_env, msg);
                enif_free_env(msg_env);
            }
        }

        outNetworkIndex = 0;
        return CHIP_NO_ERROR;
    }
    CHIP_ERROR RemoveNetwork(chip::ByteSpan ssid, chip::MutableCharSpan & outDebugText, uint8_t & outNetworkIndex) override {
        return CHIP_NO_ERROR;
    }
    CHIP_ERROR ReorderNetwork(chip::ByteSpan ssid, uint8_t index, chip::MutableCharSpan & outDebugText) override {
        return CHIP_NO_ERROR;
    }

    WiFiDriver::ScanCallback * mpScanCallback = nullptr;
    WiFiDriver::ConnectCallback * mpConnectCallback = nullptr;
};
#endif

typedef struct MatterContext {
    bool initialized;
    ErlNifPid listener_pid;
    ErlNifMonitor monitor;
    bool has_listener;
#if MATTER_SDK_ENABLED
    NervesWiFiDriver* wifi_driver;
#endif
} MatterContext;

// Global reference to context for callbacks (Matter SDK is singleton)
static MatterContext* g_matter_context = nullptr;

#if MATTER_SDK_ENABLED
static NervesWiFiDriver g_wifi_driver;
// Endpoint 0 is usually fine for network commissioning
static chip::DeviceLayer::NetworkCommissioning::Instance g_wifi_commissioning_instance(0, &g_wifi_driver);
#endif

#if MATTER_SDK_ENABLED
CHIP_ERROR NervesWiFiDriver::ScanNetworks(chip::ByteSpan ssid, WiFiDriver::ScanCallback * callback) {
    if (!g_matter_context || !g_matter_context->has_listener) {
        return CHIP_ERROR_INCORRECT_STATE;
    }
    
    mpScanCallback = callback;

    ErlNifEnv* msg_env = enif_alloc_env();
    ERL_NIF_TERM msg = enif_make_tuple2(msg_env, ATOM(msg_env, "scan_networks"), ATOM(msg_env, "undefined")); // SSID filtering not implemented yet
    enif_send(NULL, &g_matter_context->listener_pid, msg_env, msg);
    enif_free_env(msg_env);

    return CHIP_NO_ERROR;
}

CHIP_ERROR NervesWiFiDriver::ConnectNetwork(chip::ByteSpan ssid, WiFiDriver::ConnectCallback * callback) {
    if (!g_matter_context || !g_matter_context->has_listener) {
        return CHIP_ERROR_INCORRECT_STATE;
    }

    mpConnectCallback = callback;

    ErlNifEnv* msg_env = enif_alloc_env();
    if (!msg_env) {
        return CHIP_ERROR_NO_MEMORY;
    }

    // Copy SSID
    ERL_NIF_TERM ssid_term, cred_term;
    unsigned char* ssid_buf = enif_make_new_binary(msg_env, ssid.size(), &ssid_term);
    memcpy(ssid_buf, ssid.data(), ssid.size());

    // Include saved credentials from AddOrUpdateNetwork
    unsigned char* cred_buf = enif_make_new_binary(msg_env, mSavedCredentialsLength, &cred_term);
    memcpy(cred_buf, mSavedCredentials, mSavedCredentialsLength);

    // Send 3-tuple: {:connect_network, ssid, credentials}
    ERL_NIF_TERM msg = enif_make_tuple3(msg_env, ATOM(msg_env, "connect_network"), ssid_term, cred_term);
    enif_send(NULL, &g_matter_context->listener_pid, msg_env, msg);
    enif_free_env(msg_env);

    return CHIP_NO_ERROR;
}
#endif

static void matter_context_destructor(ErlNifEnv* env, void* obj) {
    MatterContext* ctx = static_cast<MatterContext*>(obj);
    if (ctx && ctx->initialized) {
#if MATTER_SDK_ENABLED
        // Cleanup Matter SDK resources
        chip::Server::GetInstance().Shutdown();
        chip::DeviceLayer::PlatformMgr().Shutdown();
#endif
        ctx->initialized = false;
    }
}

/**
 * NIF: init/0
 * Initialize the Matter SDK and return a context handle.
 *
 * Returns: {:ok, context} | {:error, reason}
 */
static ERL_NIF_TERM nif_init(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    // Allocate the Matter context resource
    MatterContext* ctx = static_cast<MatterContext*>(
        enif_alloc_resource(MATTER_CONTEXT_RESOURCE, sizeof(MatterContext))
    );

    if (!ctx) {
        return ERROR_TUPLE(env, "alloc_failed");
    }

    // Initialize the context
    ctx->initialized = false;

#if MATTER_SDK_ENABLED
    // Initialize Matter SDK
    CHIP_ERROR err = chip::DeviceLayer::PlatformMgr().InitChipStack();
    if (err != CHIP_NO_ERROR) {
        enif_release_resource(ctx);
        return ERROR_TUPLE(env, "chip_init_failed");
    }
    
    // Initialize Network Commissioning
    g_wifi_commissioning_instance.Init();
    ctx->wifi_driver = &g_wifi_driver;
#endif

    // Mark as initialized
    ctx->initialized = true;

    // Create the Erlang resource term
    ERL_NIF_TERM context_term = enif_make_resource(env, ctx);
    enif_release_resource(ctx);  // Release our reference, Erlang now owns it

    return OK_TUPLE(env, context_term);
}

/**
 * NIF: start_server/1
 * Start the Matter server (makes device discoverable/commissionable).
 *
 * Args: context
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_start_server(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    if (!ctx->initialized) {
        return ERROR_TUPLE(env, "not_initialized");
    }

#if MATTER_SDK_ENABLED
    // Start Matter server
    chip::Server::GetInstance().Init();
    chip::DeviceLayer::PlatformMgr().StartEventLoopTask();
#endif

    return OK(env);
}

/**
 * NIF: stop_server/1
 * Stop the Matter server.
 *
 * Args: context
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_stop_server(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

#if MATTER_SDK_ENABLED
    // Stop Matter server
    chip::Server::GetInstance().Shutdown();
#endif

    return OK(env);
}

/**
 * NIF: get_info/1
 * Get information about the Matter device/server state.
 *
 * Args: context
 * Returns: {:ok, info_map} | {:error, reason}
 */
static ERL_NIF_TERM nif_get_info(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    // Build info map
    ERL_NIF_TERM info_map = enif_make_new_map(env);

    // Add initialized status
    enif_make_map_put(env, info_map,
        ATOM(env, "initialized"),
        ctx->initialized ? ATOM(env, "true") : ATOM(env, "false"),
        &info_map);

    // TODO: Add more info from Matter SDK
    // - Fabric info
    // - Commissioning state
    // - Node ID
    // - etc.

    // Placeholder version info
    ERL_NIF_TERM version;
    unsigned char* version_data = enif_make_new_binary(env, 5, &version);
    memcpy(version_data, "0.1.0", 5);
    enif_make_map_put(env, info_map, ATOM(env, "nif_version"), version, &info_map);

    return OK_TUPLE(env, info_map);
}

/**
 * NIF: set_attribute/4
 * Set a Matter attribute value.
 *
 * Args: context, endpoint_id, cluster_id, attribute_id, value
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_set_attribute(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    unsigned int endpoint_id, cluster_id, attribute_id;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    if (!enif_get_uint(env, argv[1], &endpoint_id) ||
        !enif_get_uint(env, argv[2], &cluster_id) ||
        !enif_get_uint(env, argv[3], &attribute_id)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

    if (endpoint_id > 0xFFFF) {
        return ERROR_TUPLE(env, "invalid_endpoint_id");
    }

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    // Check value type and write to attribute storage
    // 1. Boolean (e.g. On/Off)
    char atom_buf[16];
    if (enif_is_atom(env, argv[4])) {
        if (enif_get_atom(env, argv[4], atom_buf, sizeof(atom_buf), ERL_NIF_LATIN1)) {
            bool val = (strcmp(atom_buf, "true") == 0);
            emberAfWriteAttribute(endpoint_id, cluster_id, attribute_id, CLUSTER_MASK_SERVER,
                                  (uint8_t*)&val, ZCL_BOOLEAN_ATTRIBUTE_TYPE);
        }
    }
    // 2. Integer (e.g. Level, Brightness)
    else {
        unsigned int uint_val;
        if (enif_get_uint(env, argv[4], &uint_val)) {
             // Assuming 8-bit unsigned for simplicity; can expand to check size
             uint8_t val = (uint8_t)uint_val;
             emberAfWriteAttribute(endpoint_id, cluster_id, attribute_id, CLUSTER_MASK_SERVER,
                                   (uint8_t*)&val, ZCL_INT8U_ATTRIBUTE_TYPE);
        }
    }

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();
#endif

    return OK(env);
}

/**
 * NIF: get_attribute/4
 * Get a Matter attribute value.
 *
 * Args: context, endpoint_id, cluster_id, attribute_id
 * Returns: {:ok, value} | {:error, reason}
 */
static ERL_NIF_TERM nif_get_attribute(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    unsigned int endpoint_id, cluster_id, attribute_id;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    if (!enif_get_uint(env, argv[1], &endpoint_id) ||
        !enif_get_uint(env, argv[2], &cluster_id) ||
        !enif_get_uint(env, argv[3], &attribute_id)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

    if (endpoint_id > 0xFFFF) {
        return ERROR_TUPLE(env, "invalid_endpoint_id");
    }

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    uint8_t data[8]; // Buffer for attribute value (max 64-bit usually enough for basic types)
    uint8_t data_type;
    EmberAfStatus status = emberAfReadAttribute(endpoint_id, cluster_id, attribute_id,
                                                CLUSTER_MASK_SERVER, data, sizeof(data), &data_type);

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();

    if (status != EMBER_ZCL_STATUS_SUCCESS) {
         return ERROR_TUPLE(env, "read_failed");
    }

    // Convert to Elixir term based on type
    if (data_type == ZCL_BOOLEAN_ATTRIBUTE_TYPE) {
        bool val = *data;
        return OK_TUPLE(env, val ? ATOM(env, "true") : ATOM(env, "false"));
    } else if (data_type == ZCL_INT8U_ATTRIBUTE_TYPE || data_type == ZCL_INT16U_ATTRIBUTE_TYPE) {
        // Simple handling for small unsigned integers
        // Note: Real implementation should handle all types and sizes
        unsigned int val = *data; // Just taking first byte for now if 8-bit
        if (data_type == ZCL_INT16U_ATTRIBUTE_TYPE) {
             val = *(uint16_t*)data;
        }
        return OK_TUPLE(env, enif_make_uint(env, val));
    }
#endif

    // Placeholder / Stub return
    return OK_TUPLE(env, enif_make_int(env, 0));
}

/**
 * NIF: open_commissioning_window/2
 * Open the commissioning window to allow controllers to pair.
 *
 * Args: context, timeout_seconds
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_open_commissioning_window(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    int timeout;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    if (!enif_get_int(env, argv[1], &timeout)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();
    CHIP_ERROR err = chip::Server::GetInstance().GetCommissioningWindowManager().OpenBasicCommissioningWindow(
        chip::System::Clock::Seconds16(timeout));
    chip::DeviceLayer::PlatformMgr().UnlockChipStack();

    if (err != CHIP_NO_ERROR) {
        return ERROR_TUPLE(env, "open_window_failed");
    }
#endif

    return OK(env);
}

/**
 * NIF: get_setup_payload/1
 * Get the QR code and manual pairing codes.
 *
 * Args: context
 * Returns: {:ok, %{qr_code: string(), manual_code: string()}} | {:error, reason}
 */
static ERL_NIF_TERM nif_get_setup_payload(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    ERL_NIF_TERM info_map = enif_make_new_map(env);

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    // Use standard utility to get payload strings
    char qrCodeBuffer[128];
    MutableCharSpan qrCode(qrCodeBuffer);
    GetQRCode(qrCode, chip::RendezvousInformationFlags(chip::RendezvousInformationFlag::kBLE));

    char manualCodeBuffer[32];
    MutableCharSpan manualCode(manualCodeBuffer);
    GetManualCode(manualCode, chip::RendezvousInformationFlags(chip::RendezvousInformationFlag::kBLE));

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();

    // Add to map
    ERL_NIF_TERM qr_val = enif_make_string(env, qrCode.data(), ERL_NIF_LATIN1);
    ERL_NIF_TERM manual_val = enif_make_string(env, manualCode.data(), ERL_NIF_LATIN1);

    enif_make_map_put(env, info_map, ATOM(env, "qr_code"), qr_val, &info_map);
    enif_make_map_put(env, info_map, ATOM(env, "manual_code"), manual_val, &info_map);
#else
    // Stub data
    enif_make_map_put(env, info_map, ATOM(env, "qr_code"), enif_make_string(env, "MT:Y.K9042C00KA0648G00", ERL_NIF_LATIN1), &info_map);
    enif_make_map_put(env, info_map, ATOM(env, "manual_code"), enif_make_string(env, "34970112332", ERL_NIF_LATIN1), &info_map);
#endif

    return OK_TUPLE(env, info_map);
}

/**
 * NIF: register_callback/1
 * Register the calling process to receive Matter events.
 *
 * Args: context
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_register_callback(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    ErlNifPid pid;
    enif_self(env, &pid);

    // If we already have a listener, we might want to demonstrate releasing it,
    // but for now we'll just overwrite/set.
    // Real implementation should probably handle monitoring to detect if the listener dies.

    ctx->listener_pid = pid;
    ctx->has_listener = true;

    // Set the global context if not already set (or update it)
    g_matter_context = ctx;

    return OK(env);
}

/**
 * NIF: factory_reset/1
 * Schedule a factory reset.
 */
static ERL_NIF_TERM nif_factory_reset(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) return ERROR_TUPLE(env, "invalid_context");

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();
    chip::Server::GetInstance().ScheduleFactoryReset();
    chip::DeviceLayer::PlatformMgr().UnlockChipStack();
#endif
    return OK(env);
}

/**
 * NIF: set_device_info/5
 * Set Device Metadata (VID, PID, Ver, Serial).
 */
static ERL_NIF_TERM nif_set_device_info(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    unsigned int vid, pid, ver;
    ErlNifBinary serial;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) return ERROR_TUPLE(env, "invalid_context");
    if (!enif_get_uint(env, argv[1], &vid) ||
        !enif_get_uint(env, argv[2], &pid) ||
        !enif_get_uint(env, argv[3], &ver) ||
        !enif_inspect_binary(env, argv[4], &serial)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

#if MATTER_SDK_ENABLED
    // Note: Writing to ConfigurationManager directly usually updates persistent storage.
    // In a real product, these might be read-only from factory data.
    // This is a "development" override.
    chip::DeviceLayer::PlatformMgr().LockChipStack();
    chip::DeviceLayer::ConfigurationMgr().StoreManufacturerDeviceId((uint16_t)vid);
    chip::DeviceLayer::ConfigurationMgr().StoreProductId((uint16_t)pid);
    chip::DeviceLayer::ConfigurationMgr().StoreSoftwareVersion((uint32_t)ver);
    
    // Serial number handling usually requires a buffer copy
    if (serial.size > 0 && serial.size < 32) {
        char serial_buf[33];
        memcpy(serial_buf, serial.data, serial.size);
        serial_buf[serial.size] = '\0';
        chip::DeviceLayer::ConfigurationMgr().StoreSerialNumber(serial_buf, serial.size);
    }
    chip::DeviceLayer::PlatformMgr().UnlockChipStack();
#endif
    return OK(env);
}

/**
 * NIF: set_commissioning_info/3
 * Set the setup PIN code and discriminator for commissioning.
 * Must be called before start_server for the values to take effect.
 *
 * Args: context, setup_pin (0-99999999), discriminator (0-4095)
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_set_commissioning_info(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    unsigned int setup_pin, discriminator;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

    if (!enif_get_uint(env, argv[1], &setup_pin) ||
        !enif_get_uint(env, argv[2], &discriminator)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

    // Validate PIN code (must be 00000001-99999998, excluding invalid patterns)
    if (setup_pin == 0 || setup_pin > 99999998) {
        return ERROR_TUPLE(env, "invalid_pin");
    }

    // Validate discriminator (12-bit value, 0-4095)
    if (discriminator > 4095) {
        return ERROR_TUPLE(env, "invalid_discriminator");
    }

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    CHIP_ERROR err = chip::DeviceLayer::ConfigurationMgr().StoreSetupPinCode(setup_pin);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_pin_failed");
    }

    err = chip::DeviceLayer::ConfigurationMgr().StoreSetupDiscriminator(discriminator);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_discriminator_failed");
    }

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();
#endif

    return OK(env);
}

/**
 * NIF: wifi_connect_result/2
 * Callback from Elixir with result of WiFi connection attempt.
 *
 * Args: context, status (0 = success, non-zero = failure)
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_wifi_connect_result(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    int status;

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }
    if (!enif_get_int(env, argv[1], &status)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

#if MATTER_SDK_ENABLED
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    if (ctx->wifi_driver && ctx->wifi_driver->mpConnectCallback) {
        chip::DeviceLayer::NetworkCommissioning::Status connStatus =
            (status == 0) ? chip::DeviceLayer::NetworkCommissioning::Status::kSuccess
                          : chip::DeviceLayer::NetworkCommissioning::Status::kNetworkNotFound;

        ctx->wifi_driver->mpConnectCallback->OnResult(connStatus, chip::CharSpan(), 0);
        ctx->wifi_driver->mpConnectCallback = nullptr;
    }

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();
#endif

    return OK(env);
}

// NIF function table
static ErlNifFunc nif_funcs[] = {
    {"nif_init", 0, nif_init, 0},
    {"nif_start_server", 1, nif_start_server, 0},
    {"nif_stop_server", 1, nif_stop_server, 0},
    {"nif_get_info", 1, nif_get_info, 0},
    {"nif_set_attribute", 5, nif_set_attribute, 0},
    {"nif_get_attribute", 4, nif_get_attribute, 0},
    {"nif_open_commissioning_window", 2, nif_open_commissioning_window, 0},
    {"nif_get_setup_payload", 1, nif_get_setup_payload, 0},
    {"nif_register_callback", 1, nif_register_callback, 0},
    {"nif_factory_reset", 1, nif_factory_reset, 0},
    {"nif_set_device_info", 5, nif_set_device_info, 0},
    {"nif_set_commissioning_info", 3, nif_set_commissioning_info, 0},
    {"nif_wifi_connect_result", 2, nif_wifi_connect_result, 0},
};

/**
 * NIF load callback - called when the module is loaded
 */
static int nif_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    // Create the resource type for Matter context
    MATTER_CONTEXT_RESOURCE = enif_open_resource_type(
        env,
        nullptr,
        "matter_context",
        matter_context_destructor,
        static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER),
        nullptr
    );

    if (!MATTER_CONTEXT_RESOURCE) {
        return -1;
    }

    return 0;
}

/**
 * NIF upgrade callback - called when the module is hot-reloaded
 */
static int nif_upgrade(ErlNifEnv* env, void** priv_data, void** old_priv_data, ERL_NIF_TERM load_info) {
    // Take over the resource type from the old module
    MATTER_CONTEXT_RESOURCE = enif_open_resource_type(
        env,
        nullptr,
        "matter_context",
        matter_context_destructor,
        static_cast<ErlNifResourceFlags>(ERL_NIF_RT_TAKEOVER),
        nullptr
    );

    return 0;
}

// NIF initialization macro
ERL_NIF_INIT(Elixir.Matterlix.Matter.NIF, nif_funcs, nif_load, nullptr, nif_upgrade, nullptr)

#if MATTER_SDK_ENABLED
/**
 * Matter SDK Callback: Called when an attribute changes.
 * We forward this event to the registered Elixir process.
 */
void MatterPostAttributeChangeCallback(const chip::app::ConcreteAttributePath & path,
                                       uint8_t type,
                                       uint16_t size,
                                       uint8_t * value)
{
    if (g_matter_context && g_matter_context->has_listener) {
        ErlNifEnv* msg_env = enif_alloc_env();

        // Decode value based on type (simplified for common types)
        ERL_NIF_TERM val_term;
        if (type == ZCL_BOOLEAN_ATTRIBUTE_TYPE) {
            val_term = (*value != 0) ? ATOM(msg_env, "true") : ATOM(msg_env, "false");
        } else if (type == ZCL_INT8U_ATTRIBUTE_TYPE) {
            val_term = enif_make_uint(msg_env, *value);
        } else if (type == ZCL_INT16U_ATTRIBUTE_TYPE && size >= 2) {
             val_term = enif_make_uint(msg_env, *(uint16_t*)value);
        } else {
             // Fallback for other types: return raw integer or binary?
             // For now, just nil, signaling "query it yourself"
             val_term = ATOM(msg_env, "nil");
        }

        ERL_NIF_TERM msg = enif_make_tuple6(msg_env,
            ATOM(msg_env, "attribute_changed"),
            enif_make_uint(msg_env, path.mEndpointId),
            enif_make_uint(msg_env, path.mClusterId),
            enif_make_uint(msg_env, path.mAttributeId),
            enif_make_uint(msg_env, type),
            val_term
        );

        enif_send(NULL, &g_matter_context->listener_pid, msg_env, msg);
        enif_free_env(msg_env);
    }
}
#endif
