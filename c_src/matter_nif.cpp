/**
 * Matter NIF - Native Implemented Functions for Matter SDK integration
 *
 * This NIF provides Elixir bindings for the Matter (formerly CHIP) SDK,
 * enabling Nerves devices to participate in Matter smart home networks.
 */

#include <erl_nif.h>
#include <cstring>
#include <string>
#include <mutex>
#include <atomic>

#if MATTER_DEBUG
#include <signal.h>
#include <unistd.h>
#endif

// Forward declarations for Matter SDK integration
#if MATTER_SDK_ENABLED
#include <app/server/Server.h>
#include <platform/CHIPDeviceLayer.h>
#include <app/util/attribute-table.h>
#include <app/util/attribute-storage.h>
#include <app-common/zap-generated/attribute-type.h>
#include <app/server/CommissioningWindowManager.h>
#include <app/clusters/network-commissioning/CodegenInstance.h>
#include <setup_payload/QRCodeSetupPayloadGenerator.h>
#include <setup_payload/OnboardingCodesUtil.h>
#include <platform/ConfigurationManager.h>
#include <platform/CommissionableDataProvider.h>
#include <platform/NetworkCommissioning.h>
#include <platform/Linux/ConfigurationManagerImpl.h>
#include <protocols/interaction_model/StatusCode.h>
#include <data-model-providers/codegen/Instance.h>
#include <LinuxCommissionableDataProvider.h>
#include <crypto/CHIPCryptoPAL.h>
#include <credentials/DeviceAttestationCredsProvider.h>
#include <credentials/examples/DeviceAttestationCredsExample.h>
#endif

// Application callbacks required by AppMain.cpp (normally provided by main.cpp)
#if MATTER_SDK_ENABLED
void ApplicationInit() {}
void ApplicationShutdown() {}
#endif

// Helper macros for creating Erlang terms
#define ATOM(env, name) enif_make_atom(env, name)
#define OK(env) ATOM(env, "ok")
#define ERROR(env) ATOM(env, "error")
#define OK_TUPLE(env, term) enif_make_tuple2(env, OK(env), term)
#define ERROR_TUPLE(env, reason) enif_make_tuple2(env, ERROR(env), ATOM(env, reason))

// Boolean atoms - these ARE the correct Elixir true/false values
#define BOOL_TRUE(env) enif_make_atom(env, "true")
#define BOOL_FALSE(env) enif_make_atom(env, "false")

// Guard macro: return {:error, :not_started} if SDK is not initialized
#if MATTER_SDK_ENABLED
#define REQUIRE_SDK_INITIALIZED(env) do { \
    std::lock_guard<std::mutex> _guard(get_global_mutex()); \
    if (!g_singleton || !g_singleton->server_started) { \
        return ERROR_TUPLE(env, "not_started"); \
    } \
} while(0)
#else
#define REQUIRE_SDK_INITIALIZED(env) ((void)0)
#endif

// Resource type for Matter context (will hold Matter SDK state)
static ErlNifResourceType* MATTER_CONTEXT_RESOURCE = nullptr;


// Forward declaration for MatterContext
struct MatterContext;

// Global mutex - using Meyer's singleton pattern for thread-safe initialization.
// The mutex pointer is intentionally leaked to avoid C++ static destructor race
// with BEAM shutdown. This is a well-known pattern for mixing C++ with Erlang NIFs.
static std::mutex& get_global_mutex() {
    // C++11 guarantees thread-safe initialization of static locals
    static std::mutex* g_nif_mutex = new std::mutex();  // Intentionally never deleted
    return *g_nif_mutex;
}

// Singleton holder stored in NIF priv_data for thread-safe SDK access
struct MatterSingleton {
    MatterContext* owner_context;     // The context that owns SDK lifecycle
    std::atomic<int> ref_count;       // Number of Elixir resources referencing this
    bool sdk_initialized;
    bool server_started;              // True after Server::Init() + StartEventLoopTask()

    MatterSingleton() : owner_context(nullptr), ref_count(0), sdk_initialized(false), server_started(false) {}

    // Use the global mutex for thread safety
    static std::mutex& mutex() { return get_global_mutex(); }
};

#if MATTER_SDK_ENABLED
// Simple NetworkIterator for a single WiFi network
class SingleNetworkIterator : public chip::DeviceLayer::NetworkCommissioning::NetworkIterator {
public:
    SingleNetworkIterator(const chip::DeviceLayer::NetworkCommissioning::Network* network, bool hasNetwork)
        : mNetwork(network), mHasNetwork(hasNetwork), mExhausted(false) {}

    size_t Count() override { return mHasNetwork ? 1 : 0; }
    bool Next(chip::DeviceLayer::NetworkCommissioning::Network & item) override {
        if (!mHasNetwork || mExhausted) return false;
        mExhausted = true;
        item = *mNetwork;
        return true;
    }
    void Release() override { delete this; }

private:
    const chip::DeviceLayer::NetworkCommissioning::Network* mNetwork;
    bool mHasNetwork;
    bool mExhausted;
};

class NervesWiFiDriver : public chip::DeviceLayer::NetworkCommissioning::WiFiDriver {
public:
    using Status = chip::DeviceLayer::NetworkCommissioning::Status;

    // Network storage structure
    struct StoredNetwork {
        uint8_t ssid[32];
        size_t ssidLength;
        uint8_t credentials[64];
        size_t credentialsLength;
        bool configured;
    };

    StoredNetwork mNetwork = {};
    chip::DeviceLayer::NetworkCommissioning::Network mNetworkInfo = {};

    CHIP_ERROR Init(chip::DeviceLayer::NetworkCommissioning::Internal::BaseDriver::NetworkStatusChangeCallback * statusChangeCallback) override { return CHIP_NO_ERROR; }
    void Shutdown() override { }
    uint8_t GetMaxNetworks() override { return 1; }
    uint8_t GetScanNetworkTimeoutSeconds() override { return 10; }
    uint8_t GetConnectNetworkTimeoutSeconds() override { return 20; }
    CHIP_ERROR CommitConfiguration() override { return CHIP_NO_ERROR; }
    CHIP_ERROR RevertConfiguration() override { return CHIP_NO_ERROR; }

    void ScanNetworks(chip::ByteSpan ssid, WiFiDriver::ScanCallback * callback) override;
    void ConnectNetwork(chip::ByteSpan ssid, WiFiDriver::ConnectCallback * callback) override;

    chip::DeviceLayer::NetworkCommissioning::NetworkIterator * GetNetworks() override {
        if (mNetwork.configured) {
            memcpy(mNetworkInfo.networkID, mNetwork.ssid, mNetwork.ssidLength);
            mNetworkInfo.networkIDLen = static_cast<uint8_t>(mNetwork.ssidLength);
            mNetworkInfo.connected = false;
        }
        return new SingleNetworkIterator(&mNetworkInfo, mNetwork.configured);
    }

    Status AddOrUpdateNetwork(chip::ByteSpan ssid, chip::ByteSpan credentials,
                              chip::MutableCharSpan & outDebugText, uint8_t & outNetworkIndex) override;

    Status RemoveNetwork(chip::ByteSpan ssid, chip::MutableCharSpan & outDebugText, uint8_t & outNetworkIndex) override {
        mNetwork.configured = false;
        outNetworkIndex = 0;
        return Status::kSuccess;
    }

    Status ReorderNetwork(chip::ByteSpan ssid, uint8_t index, chip::MutableCharSpan & outDebugText) override {
        return Status::kSuccess;
    }

    WiFiDriver::ScanCallback * mpScanCallback = nullptr;
    WiFiDriver::ConnectCallback * mpConnectCallback = nullptr;
};
#endif

typedef struct MatterContext {
    bool initialized;
    bool is_owner;              // True if this context owns SDK lifecycle
    ErlNifPid listener_pid;
    ErlNifMonitor monitor;
    bool has_listener;
    bool monitor_active;        // True if process monitor is currently active
#if MATTER_SDK_ENABLED
    NervesWiFiDriver* wifi_driver;
#endif
} MatterContext;

#if MATTER_SDK_ENABLED
static NervesWiFiDriver g_wifi_driver;
// Endpoint 0 is usually fine for network commissioning
static chip::app::Clusters::NetworkCommissioning::Instance g_wifi_commissioning_instance(0, &g_wifi_driver);

// Global singleton pointer - protected by get_global_mutex()
static MatterSingleton* g_singleton = nullptr;

// Helper to safely get listener context for callbacks.
// Acquires lock BEFORE reading g_singleton to avoid TOCTOU race condition.
static bool get_listener_info(ErlNifPid* out_pid) {
    std::lock_guard<std::mutex> lock(get_global_mutex());

    MatterSingleton* singleton = g_singleton;
    if (!singleton) return false;

    if (singleton->owner_context && singleton->owner_context->has_listener) {
        *out_pid = singleton->owner_context->listener_pid;
        return true;
    }
    return false;
}

void NervesWiFiDriver::ScanNetworks(chip::ByteSpan ssid, WiFiDriver::ScanCallback * callback) {
    ErlNifPid pid;
    if (!get_listener_info(&pid)) {
        callback->OnFinished(Status::kUnknownError, chip::CharSpan(), nullptr);
        return;
    }

    mpScanCallback = callback;

    ErlNifEnv* msg_env = enif_alloc_env();
    if (!msg_env) {
        callback->OnFinished(Status::kUnknownError, chip::CharSpan(), nullptr);
        return;
    }

    ERL_NIF_TERM msg = enif_make_tuple2(msg_env, ATOM(msg_env, "scan_networks"), ATOM(msg_env, "undefined"));
    enif_send(NULL, &pid, msg_env, msg);
    enif_free_env(msg_env);
}

void NervesWiFiDriver::ConnectNetwork(chip::ByteSpan ssid, WiFiDriver::ConnectCallback * callback) {
    ErlNifPid pid;
    if (!get_listener_info(&pid)) {
        callback->OnResult(Status::kUnknownError, chip::CharSpan(), 0);
        return;
    }

    mpConnectCallback = callback;

    ErlNifEnv* msg_env = enif_alloc_env();
    if (!msg_env) {
        callback->OnResult(Status::kUnknownError, chip::CharSpan(), 0);
        return;
    }

    // Copy SSID
    ERL_NIF_TERM ssid_term, cred_term;
    unsigned char* ssid_buf = enif_make_new_binary(msg_env, ssid.size(), &ssid_term);
    if (!ssid_buf) {
        enif_free_env(msg_env);
        callback->OnResult(Status::kUnknownError, chip::CharSpan(), 0);
        return;
    }
    memcpy(ssid_buf, ssid.data(), ssid.size());

    // Include saved credentials from AddOrUpdateNetwork
    unsigned char* cred_buf = enif_make_new_binary(msg_env, mNetwork.credentialsLength, &cred_term);
    if (!cred_buf) {
        enif_free_env(msg_env);
        callback->OnResult(Status::kUnknownError, chip::CharSpan(), 0);
        return;
    }
    memcpy(cred_buf, mNetwork.credentials, mNetwork.credentialsLength);

    // Send 3-tuple: {:connect_network, ssid, credentials}
    ERL_NIF_TERM msg = enif_make_tuple3(msg_env, ATOM(msg_env, "connect_network"), ssid_term, cred_term);
    enif_send(NULL, &pid, msg_env, msg);
    enif_free_env(msg_env);
}

NervesWiFiDriver::Status NervesWiFiDriver::AddOrUpdateNetwork(chip::ByteSpan ssid, chip::ByteSpan credentials,
                              chip::MutableCharSpan & outDebugText, uint8_t & outNetworkIndex) {
    // Store credentials in our network struct
    mNetwork.ssidLength = std::min(ssid.size(), sizeof(mNetwork.ssid));
    memcpy(mNetwork.ssid, ssid.data(), mNetwork.ssidLength);

    mNetwork.credentialsLength = std::min(credentials.size(), sizeof(mNetwork.credentials));
    memcpy(mNetwork.credentials, credentials.data(), mNetwork.credentialsLength);
    mNetwork.configured = true;

    // Notify Elixir about the new network
    ErlNifPid pid;
    if (get_listener_info(&pid)) {
        ErlNifEnv* msg_env = enif_alloc_env();
        if (msg_env) {
            ERL_NIF_TERM ssid_term, cred_term;
            unsigned char* buf;

            buf = enif_make_new_binary(msg_env, ssid.size(), &ssid_term);
            if (!buf) {
                enif_free_env(msg_env);
                outNetworkIndex = 0;
                return Status::kSuccess;  // Non-fatal: network stored, just couldn't notify
            }
            memcpy(buf, ssid.data(), ssid.size());

            buf = enif_make_new_binary(msg_env, credentials.size(), &cred_term);
            if (!buf) {
                enif_free_env(msg_env);
                outNetworkIndex = 0;
                return Status::kSuccess;  // Non-fatal: network stored, just couldn't notify
            }
            memcpy(buf, credentials.data(), credentials.size());

            ERL_NIF_TERM msg = enif_make_tuple3(msg_env, ATOM(msg_env, "add_network"), ssid_term, cred_term);
            enif_send(NULL, &pid, msg_env, msg);
            enif_free_env(msg_env);
        }
    }

    outNetworkIndex = 0;
    return Status::kSuccess;
}
#endif
static void matter_context_destructor(ErlNifEnv* env, void* obj) {
    MatterContext* ctx = static_cast<MatterContext*>(obj);
    if (!ctx) return;

    // Get singleton from priv_data
    MatterSingleton* singleton = static_cast<MatterSingleton*>(enif_priv_data(env));
    if (!singleton) return;

    std::lock_guard<std::mutex> lock(MatterSingleton::mutex());

    singleton->ref_count--;

    // Only shut down SDK if this was the owner and no more references
    if (ctx->is_owner && singleton->ref_count <= 0 && ctx->initialized) {
#if MATTER_SDK_ENABLED
        chip::Server::GetInstance().Shutdown();
        chip::DeviceLayer::PlatformMgr().Shutdown();
#endif
        singleton->sdk_initialized = false;
        singleton->owner_context = nullptr;
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
    MatterSingleton* singleton = static_cast<MatterSingleton*>(enif_priv_data(env));
    if (!singleton) {
        return ERROR_TUPLE(env, "no_priv_data");
    }

    std::lock_guard<std::mutex> lock(MatterSingleton::mutex());

    // Allocate a new context resource
    MatterContext* ctx = static_cast<MatterContext*>(
        enif_alloc_resource(MATTER_CONTEXT_RESOURCE, sizeof(MatterContext))
    );

    if (!ctx) {
        return ERROR_TUPLE(env, "alloc_failed");
    }

    // Initialize the context
    memset(ctx, 0, sizeof(MatterContext));

    // If SDK already initialized, this context shares it but doesn't own lifecycle
    if (singleton->sdk_initialized && singleton->owner_context) {
        ctx->initialized = true;
        ctx->is_owner = false;
#if MATTER_SDK_ENABLED
        ctx->wifi_driver = &g_wifi_driver;
#endif
        singleton->ref_count++;

        ERL_NIF_TERM context_term = enif_make_resource(env, ctx);
        enif_release_resource(ctx);
        return OK_TUPLE(env, context_term);
    }

    // First initialization - this context owns the SDK lifecycle
    ctx->is_owner = true;

#if MATTER_SDK_ENABLED
    // Initialize Matter SDK
    CHIP_ERROR err = chip::DeviceLayer::PlatformMgr().InitChipStack();
    if (err != CHIP_NO_ERROR) {
        enif_release_resource(ctx);
        return ERROR_TUPLE(env, "chip_init_failed");
    }

    // Initialize Network Commissioning
    err = g_wifi_commissioning_instance.Init();
    if (err != CHIP_NO_ERROR) {
        enif_release_resource(ctx);
        return ERROR_TUPLE(env, "wifi_commissioning_init_failed");
    }
    ctx->wifi_driver = &g_wifi_driver;
#endif

    // Mark as initialized
    ctx->initialized = true;
    singleton->sdk_initialized = true;
    singleton->owner_context = ctx;
    singleton->ref_count = 1;

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

#if MATTER_DEBUG
    // Debug: write progress to persistent file (survives reboots on Nerves)
    auto dbg = [](const char* msg) {
        FILE* f = fopen("/data/matter_debug.log", "a");
        if (f) { fprintf(f, "%s\n", msg); fclose(f); sync(); }
    };

    dbg("=== nif_start_server begin ===");

    // Install signal handler to catch crashes inside Server::Init()
    static auto s_dbg = dbg;
    struct sigaction sa = {};
    sa.sa_handler = [](int sig) {
        fflush(stdout);
        fflush(stderr);
        fsync(STDOUT_FILENO);
        fsync(STDERR_FILENO);
        s_dbg(sig == SIGSEGV ? "CRASH: SIGSEGV (null pointer / bad memory access)"
             : sig == SIGABRT ? "CRASH: SIGABRT (VerifyOrDie / abort called)"
             : sig == SIGBUS  ? "CRASH: SIGBUS (bus error)"
             : "CRASH: unknown signal");
        _exit(1);
    };
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGABRT, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);

    // Redirect stdout and stderr to debug file (ChipLog uses printf/stdout)
    {
        FILE* dbgFile = fopen("/data/matter_debug.log", "a");
        if (dbgFile) {
            int dbgFd = fileno(dbgFile);
            dup2(dbgFd, STDOUT_FILENO);
            dup2(dbgFd, STDERR_FILENO);
            fclose(dbgFile);
            setvbuf(stdout, nullptr, _IOLBF, 0);
            setvbuf(stderr, nullptr, _IOLBF, 0);
        }
    }
#endif // MATTER_DEBUG

    static chip::CommonCaseDeviceServerInitParams initParams;
    CHIP_ERROR err = initParams.InitializeStaticResourcesBeforeServerInit();
    if (err != CHIP_NO_ERROR) {
        return ERROR_TUPLE(env, "init_params_failed");
    }

    // Set the data model provider (required since Matter SDK added this field)
    initParams.dataModelProvider = chip::app::CodegenDataModelProviderInstance(initParams.persistentStorageDelegate);

    // Set up CommissionableDataProvider (required - VerifyOrDie in GetCommissionableDataProvider)
    // Use default test values: passcode 20202021, discriminator 3840
    {
        static LinuxCommissionableDataProvider sCommissionableDataProvider;
        err = sCommissionableDataProvider.Init(
            chip::NullOptional,  // no serialized SPAKE2+ verifier
            chip::NullOptional,  // no salt (will be randomly generated)
            chip::Crypto::kSpake2p_Min_PBKDF_Iterations,
            chip::MakeOptional(static_cast<uint32_t>(20202021)),  // default test passcode
            3840  // default test discriminator
        );
        if (err != CHIP_NO_ERROR) {
            return ERROR_TUPLE(env, "commissionable_data_init_failed");
        }
        chip::DeviceLayer::SetCommissionableDataProvider(&sCommissionableDataProvider);
    }

    // Ensure GeneralCommissioning attributes are initialized
    // ConfigurationManagerImpl::Init() should do this but silently fails on Nerves
    {
        using PosixConfig = chip::DeviceLayer::Internal::PosixConfig;

        PosixConfig::EnsureNamespace(PosixConfig::kConfigNamespace_ChipConfig);

        if (!PosixConfig::ConfigValueExists(PosixConfig::kConfigKey_RegulatoryLocation)) {
            uint32_t loc = 0; // Indoor
            PosixConfig::WriteConfigValue(PosixConfig::kConfigKey_RegulatoryLocation, loc);
        }

        if (!PosixConfig::ConfigValueExists(PosixConfig::kConfigKey_LocationCapability)) {
            uint32_t loc = 2; // IndoorOutdoor
            PosixConfig::WriteConfigValue(PosixConfig::kConfigKey_LocationCapability, loc);
        }
    }

    // Set up Device Attestation Credentials provider (required for commissioning)
    chip::Credentials::SetDeviceAttestationCredentialsProvider(
        chip::Credentials::Examples::GetExampleDACProvider());

    err = chip::Server::GetInstance().Init(initParams);
    if (err != CHIP_NO_ERROR) {
        return ERROR_TUPLE(env, "server_init_failed");
    }

    err = chip::DeviceLayer::PlatformMgr().StartEventLoopTask();
    if (err != CHIP_NO_ERROR) {
        return ERROR_TUPLE(env, "event_loop_failed");
    }

    {
        std::lock_guard<std::mutex> lock(get_global_mutex());
        if (g_singleton) g_singleton->server_started = true;
    }
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

    if (!ctx->initialized) {
        return ERROR_TUPLE(env, "not_initialized");
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

    // Add initialized status - use proper Elixir boolean atoms
    enif_make_map_put(env, info_map,
        ATOM(env, "initialized"),
        ctx->initialized ? BOOL_TRUE(env) : BOOL_FALSE(env),
        &info_map);

    // Add is_owner flag
    enif_make_map_put(env, info_map,
        ATOM(env, "is_owner"),
        ctx->is_owner ? BOOL_TRUE(env) : BOOL_FALSE(env),
        &info_map);

    // Add has_listener flag
    enif_make_map_put(env, info_map,
        ATOM(env, "has_listener"),
        ctx->has_listener ? BOOL_TRUE(env) : BOOL_FALSE(env),
        &info_map);

    // Placeholder version info
    ERL_NIF_TERM version;
    unsigned char* version_data = enif_make_new_binary(env, 5, &version);
    if (version_data) {
        memcpy(version_data, "0.2.0", 5);
        enif_make_map_put(env, info_map, ATOM(env, "nif_version"), version, &info_map);
    }

    return OK_TUPLE(env, info_map);
}

/**
 * NIF: set_attribute/5
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
    REQUIRE_SDK_INITIALIZED(env);
    using Status = chip::Protocols::InteractionModel::Status;

    chip::DeviceLayer::PlatformMgr().LockChipStack();

    // Look up attribute metadata to determine the correct type
    const EmberAfAttributeMetadata * metadata = emberAfLocateAttributeMetadata(
        static_cast<chip::EndpointId>(endpoint_id),
        static_cast<chip::ClusterId>(cluster_id),
        static_cast<chip::AttributeId>(attribute_id));

    Status write_status = Status::Failure;

    if (metadata != nullptr) {
        EmberAfAttributeType attrType = metadata->attributeType;

        // Check value type and write to attribute storage
        // 1. Boolean (e.g. On/Off)
        char atom_buf[16];
        if (enif_is_atom(env, argv[4])) {
            if (enif_get_atom(env, argv[4], atom_buf, sizeof(atom_buf), ERL_NIF_LATIN1)) {
                bool val = (strcmp(atom_buf, "true") == 0);
                write_status = emberAfWriteAttribute(
                    static_cast<chip::EndpointId>(endpoint_id),
                    static_cast<chip::ClusterId>(cluster_id),
                    static_cast<chip::AttributeId>(attribute_id),
                    (uint8_t*)&val, ZCL_BOOLEAN_ATTRIBUTE_TYPE);
            }
        }
        // 2. Integer - use the attribute's actual type from metadata
        else {
            unsigned int uint_val;
            if (enif_get_uint(env, argv[4], &uint_val)) {
                if (attrType == ZCL_INT8U_ATTRIBUTE_TYPE || attrType == ZCL_BOOLEAN_ATTRIBUTE_TYPE) {
                    uint8_t val = (uint8_t)uint_val;
                    write_status = emberAfWriteAttribute(
                        static_cast<chip::EndpointId>(endpoint_id),
                        static_cast<chip::ClusterId>(cluster_id),
                        static_cast<chip::AttributeId>(attribute_id),
                        (uint8_t*)&val, attrType);
                } else if (attrType == ZCL_INT16U_ATTRIBUTE_TYPE) {
                    uint16_t val = (uint16_t)uint_val;
                    write_status = emberAfWriteAttribute(
                        static_cast<chip::EndpointId>(endpoint_id),
                        static_cast<chip::ClusterId>(cluster_id),
                        static_cast<chip::AttributeId>(attribute_id),
                        (uint8_t*)&val, attrType);
                } else {
                    uint32_t val = (uint32_t)uint_val;
                    write_status = emberAfWriteAttribute(
                        static_cast<chip::EndpointId>(endpoint_id),
                        static_cast<chip::ClusterId>(cluster_id),
                        static_cast<chip::AttributeId>(attribute_id),
                        (uint8_t*)&val, attrType);
                }
            }
        }
    }

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();

    if (write_status != Status::Success) {
        return ERROR_TUPLE(env, "write_failed");
    }
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
    REQUIRE_SDK_INITIALIZED(env);
    using Status = chip::Protocols::InteractionModel::Status;

    chip::DeviceLayer::PlatformMgr().LockChipStack();

    // Look up attribute metadata to determine the type
    const EmberAfAttributeMetadata * metadata = emberAfLocateAttributeMetadata(
        static_cast<chip::EndpointId>(endpoint_id),
        static_cast<chip::ClusterId>(cluster_id),
        static_cast<chip::AttributeId>(attribute_id));

    if (metadata == nullptr) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "attribute_not_found");
    }

    EmberAfAttributeType data_type = metadata->attributeType;

    uint8_t data[8]; // Buffer for attribute value (max 64-bit usually enough for basic types)
    Status status = emberAfReadAttribute(
        static_cast<chip::EndpointId>(endpoint_id),
        static_cast<chip::ClusterId>(cluster_id),
        static_cast<chip::AttributeId>(attribute_id),
        data, sizeof(data));

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();

    if (status != Status::Success) {
         return ERROR_TUPLE(env, "read_failed");
    }

    // Convert to Elixir term based on type - use proper boolean atoms
    // Use memcpy for all multi-byte values to avoid unaligned access on ARM
    if (data_type == ZCL_BOOLEAN_ATTRIBUTE_TYPE) {
        bool val = *data;
        return OK_TUPLE(env, val ? BOOL_TRUE(env) : BOOL_FALSE(env));
    } else if (data_type == ZCL_INT8U_ATTRIBUTE_TYPE) {
        return OK_TUPLE(env, enif_make_uint(env, *data));
    } else if (data_type == ZCL_INT8S_ATTRIBUTE_TYPE) {
        return OK_TUPLE(env, enif_make_int(env, (int8_t)*data));
    } else if (data_type == ZCL_INT16U_ATTRIBUTE_TYPE) {
        uint16_t val;
        memcpy(&val, data, sizeof(val));
        return OK_TUPLE(env, enif_make_uint(env, val));
    } else if (data_type == ZCL_INT16S_ATTRIBUTE_TYPE) {
        int16_t val;
        memcpy(&val, data, sizeof(val));
        return OK_TUPLE(env, enif_make_int(env, val));
    } else if (data_type == ZCL_INT32U_ATTRIBUTE_TYPE) {
        uint32_t val;
        memcpy(&val, data, sizeof(val));
        return OK_TUPLE(env, enif_make_uint(env, val));
    } else if (data_type == ZCL_INT32S_ATTRIBUTE_TYPE) {
        int32_t val;
        memcpy(&val, data, sizeof(val));
        return OK_TUPLE(env, enif_make_int(env, val));
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

    // Validate timeout is positive and fits in 16-bit seconds
    if (timeout <= 0 || timeout > 65535) {
        return ERROR_TUPLE(env, "invalid_timeout");
    }

#if MATTER_SDK_ENABLED
    REQUIRE_SDK_INITIALIZED(env);
    chip::DeviceLayer::PlatformMgr().LockChipStack();
    CHIP_ERROR err = chip::Server::GetInstance().GetCommissioningWindowManager().OpenBasicCommissioningWindow(
        chip::System::Clock::Seconds16(static_cast<uint16_t>(timeout)));
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
    REQUIRE_SDK_INITIALIZED(env);

    chip::DeviceLayer::PlatformMgr().LockChipStack();

    // QR codes can be ~200 chars, manual codes up to 21 digits
    // Use generous buffers and ensure null termination
    char qrCodeBuffer[256] = {0};
    chip::MutableCharSpan qrCode(qrCodeBuffer, sizeof(qrCodeBuffer) - 1);
    CHIP_ERROR qrErr = GetQRCode(qrCode, chip::RendezvousInformationFlags(chip::RendezvousInformationFlag::kBLE));

    char manualCodeBuffer[64] = {0};
    chip::MutableCharSpan manualCode(manualCodeBuffer, sizeof(manualCodeBuffer) - 1);
    CHIP_ERROR manualErr = GetManualPairingCode(manualCode, chip::RendezvousInformationFlags(chip::RendezvousInformationFlag::kBLE));

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();

    // Ensure null termination (MutableCharSpan doesn't guarantee it)
    qrCodeBuffer[qrCode.size()] = '\0';
    manualCodeBuffer[manualCode.size()] = '\0';

    // Add to map - use empty string if generation failed
    const char* qr_str = (qrErr == CHIP_NO_ERROR) ? qrCodeBuffer : "";
    const char* manual_str = (manualErr == CHIP_NO_ERROR) ? manualCodeBuffer : "";

    ERL_NIF_TERM qr_val = enif_make_string(env, qr_str, ERL_NIF_LATIN1);
    ERL_NIF_TERM manual_val = enif_make_string(env, manual_str, ERL_NIF_LATIN1);

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
 * Note: Process monitoring is disabled to avoid BEAM shutdown race conditions.
 * If the registered process dies, messages will be sent to a dead PID (no harm).
 * The GenServer should handle this via supervision.
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

    // Synchronize with get_listener_info() which reads these fields
    std::lock_guard<std::mutex> lock(get_global_mutex());
    ctx->listener_pid = pid;
    ctx->has_listener = true;
    ctx->monitor_active = false;

    return OK(env);
}

/**
 * NIF: factory_reset/1
 * Schedule a factory reset.
 */
static ERL_NIF_TERM nif_factory_reset(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    MatterContext* ctx;
    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }

#if MATTER_SDK_ENABLED
    REQUIRE_SDK_INITIALIZED(env);
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

    if (!enif_get_resource(env, argv[0], MATTER_CONTEXT_RESOURCE, (void**)&ctx)) {
        return ERROR_TUPLE(env, "invalid_context");
    }
    if (!enif_get_uint(env, argv[1], &vid) ||
        !enif_get_uint(env, argv[2], &pid) ||
        !enif_get_uint(env, argv[3], &ver) ||
        !enif_inspect_binary(env, argv[4], &serial)) {
        return ERROR_TUPLE(env, "invalid_args");
    }

    // Validate VID and PID are 16-bit values
    if (vid > 0xFFFF) {
        return ERROR_TUPLE(env, "invalid_vendor_id");
    }
    if (pid > 0xFFFF) {
        return ERROR_TUPLE(env, "invalid_product_id");
    }

    // Validate serial number length (Matter spec allows up to 32 chars)
    if (serial.size == 0 || serial.size > 32) {
        return ERROR_TUPLE(env, "invalid_serial_number");
    }

#if MATTER_SDK_ENABLED
    REQUIRE_SDK_INITIALIZED(env);
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    // Use Linux platform-specific ConfigurationManagerImpl for VID/PID
    auto & configImpl = chip::DeviceLayer::ConfigurationManagerImpl::GetDefaultInstance();
    CHIP_ERROR err;

    err = configImpl.StoreVendorId((uint16_t)vid);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_vendor_id_failed");
    }

    err = configImpl.StoreProductId((uint16_t)pid);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_product_id_failed");
    }

    err = chip::DeviceLayer::ConfigurationMgr().StoreSoftwareVersion((uint32_t)ver);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_software_version_failed");
    }

    // Serial number handling - already validated above
    char serial_buf[33];
    memcpy(serial_buf, serial.data, serial.size);
    serial_buf[serial.size] = '\0';
    err = chip::DeviceLayer::ConfigurationMgr().StoreSerialNumber(serial_buf, serial.size);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_serial_number_failed");
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
    REQUIRE_SDK_INITIALIZED(env);
    chip::DeviceLayer::PlatformMgr().LockChipStack();

    auto * commissionableDataProvider = chip::DeviceLayer::GetCommissionableDataProvider();
    if (!commissionableDataProvider) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "no_commissionable_data_provider");
    }

    CHIP_ERROR err = commissionableDataProvider->SetSetupPasscode(setup_pin);
    if (err != CHIP_NO_ERROR) {
        chip::DeviceLayer::PlatformMgr().UnlockChipStack();
        return ERROR_TUPLE(env, "store_pin_failed");
    }

    err = commissionableDataProvider->SetSetupDiscriminator(static_cast<uint16_t>(discriminator));
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

/**
 * NIF: wifi_scan_result/2
 * Report WiFi scan results back to Matter SDK.
 *
 * Args: context, status (0 = success with no results for now)
 * Returns: :ok | {:error, reason}
 */
static ERL_NIF_TERM nif_wifi_scan_result(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
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

    if (ctx->wifi_driver && ctx->wifi_driver->mpScanCallback) {
        chip::DeviceLayer::NetworkCommissioning::Status scanStatus =
            (status == 0) ? chip::DeviceLayer::NetworkCommissioning::Status::kSuccess
                          : chip::DeviceLayer::NetworkCommissioning::Status::kUnknownError;

        // Signal scan complete - full implementation would pass actual network list
        ctx->wifi_driver->mpScanCallback->OnFinished(scanStatus, chip::CharSpan(), nullptr);
        ctx->wifi_driver->mpScanCallback = nullptr;
    }

    chip::DeviceLayer::PlatformMgr().UnlockChipStack();
#endif

    return OK(env);
}

// NIF function table
// Note: Dirty scheduler flags (ERL_NIF_DIRTY_JOB_IO_BOUND) should be enabled
// when Matter SDK is enabled, as those calls may block. For stub mode, we use
// regular schedulers to avoid BEAM threading complications during testing.
#if MATTER_SDK_ENABLED
static ErlNifFunc nif_funcs[] = {
    {"nif_init", 0, nif_init, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_start_server", 1, nif_start_server, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_stop_server", 1, nif_stop_server, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_get_info", 1, nif_get_info, 0},
    {"nif_set_attribute", 5, nif_set_attribute, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_get_attribute", 4, nif_get_attribute, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_open_commissioning_window", 2, nif_open_commissioning_window, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_get_setup_payload", 1, nif_get_setup_payload, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_register_callback", 1, nif_register_callback, 0},
    {"nif_factory_reset", 1, nif_factory_reset, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_set_device_info", 5, nif_set_device_info, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_set_commissioning_info", 3, nif_set_commissioning_info, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_wifi_connect_result", 2, nif_wifi_connect_result, ERL_NIF_DIRTY_JOB_IO_BOUND},
    {"nif_wifi_scan_result", 2, nif_wifi_scan_result, ERL_NIF_DIRTY_JOB_IO_BOUND},
};
#else
// Stub mode - no blocking calls, use regular schedulers
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
    {"nif_wifi_scan_result", 2, nif_wifi_scan_result, 0},
};
#endif

/**
 * NIF load callback - called when the module is loaded
 */
static int nif_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    // Allocate singleton holder
    MatterSingleton* singleton = new (std::nothrow) MatterSingleton();
    if (!singleton) {
        return -1;
    }
    *priv_data = singleton;

#if MATTER_SDK_ENABLED
    g_singleton = singleton;
#endif

    // Create resource type
    // Note: Using enif_open_resource_type instead of enif_open_resource_type_x
    // to avoid potential issues with the down callback during BEAM shutdown.
    MATTER_CONTEXT_RESOURCE = enif_open_resource_type(
        env,
        nullptr,
        "matter_context",
        matter_context_destructor,
        static_cast<ErlNifResourceFlags>(ERL_NIF_RT_CREATE | ERL_NIF_RT_TAKEOVER),
        nullptr
    );

    if (!MATTER_CONTEXT_RESOURCE) {
        delete singleton;
        return -1;
    }

    return 0;
}

/**
 * NIF unload callback - cleanup when module is unloaded
 */
static void nif_unload(ErlNifEnv* env, void* priv_data) {
    MatterSingleton* singleton = static_cast<MatterSingleton*>(priv_data);
    if (singleton) {
#if MATTER_SDK_ENABLED
        {
            std::lock_guard<std::mutex> lock(get_global_mutex());
            g_singleton = nullptr;
        }
#endif
        delete singleton;
    }
}

/**
 * NIF upgrade callback - called when the module is hot-reloaded
 */
static int nif_upgrade(ErlNifEnv* env, void** priv_data, void** old_priv_data, ERL_NIF_TERM load_info) {
    // Take over singleton from old module
    *priv_data = *old_priv_data;

#if MATTER_SDK_ENABLED
    g_singleton = static_cast<MatterSingleton*>(*priv_data);
#endif

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
// Signature: ERL_NIF_INIT(MODULE, FUNCS, LOAD, RELOAD, UPGRADE, UNLOAD)
// RELOAD is deprecated and should be NULL
ERL_NIF_INIT(Elixir.Matterlix.Matter.NIF, nif_funcs, nif_load, nullptr, nif_upgrade, nif_unload)

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
    ErlNifPid pid;
    if (!get_listener_info(&pid)) {
        return;  // No listener registered
    }

    ErlNifEnv* msg_env = enif_alloc_env();
    if (!msg_env) {
        return;
    }

    // Decode value based on type
    // Use memcpy for all multi-byte values to avoid unaligned access on ARM
    ERL_NIF_TERM val_term;
    if (type == ZCL_BOOLEAN_ATTRIBUTE_TYPE) {
        val_term = (*value != 0) ? BOOL_TRUE(msg_env) : BOOL_FALSE(msg_env);
    } else if (type == ZCL_INT8U_ATTRIBUTE_TYPE) {
        val_term = enif_make_uint(msg_env, *value);
    } else if (type == ZCL_INT8S_ATTRIBUTE_TYPE) {
        val_term = enif_make_int(msg_env, (int8_t)*value);
    } else if (type == ZCL_INT16U_ATTRIBUTE_TYPE && size >= 2) {
        uint16_t tmp;
        memcpy(&tmp, value, sizeof(tmp));
        val_term = enif_make_uint(msg_env, tmp);
    } else if (type == ZCL_INT16S_ATTRIBUTE_TYPE && size >= 2) {
        int16_t tmp;
        memcpy(&tmp, value, sizeof(tmp));
        val_term = enif_make_int(msg_env, tmp);
    } else if (type == ZCL_INT32U_ATTRIBUTE_TYPE && size >= 4) {
        uint32_t tmp;
        memcpy(&tmp, value, sizeof(tmp));
        val_term = enif_make_uint(msg_env, tmp);
    } else if (type == ZCL_INT32S_ATTRIBUTE_TYPE && size >= 4) {
        int32_t tmp;
        memcpy(&tmp, value, sizeof(tmp));
        val_term = enif_make_int(msg_env, tmp);
    } else {
        // Fallback for other types: return nil, signaling "query it yourself"
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

    enif_send(NULL, &pid, msg_env, msg);
    enif_free_env(msg_env);
}
#endif
