/**
 * Matter NIF - Native Implemented Functions for Matter SDK integration
 *
 * This NIF provides Elixir bindings for the Matter (formerly CHIP) SDK,
 * enabling Nerves devices to participate in Matter smart home networks.
 */

#include <erl_nif.h>
#include <cstring>
#include <string>

// Forward declarations for Matter SDK integration (to be implemented)
// #include <app/server/Server.h>
// #include <platform/CHIPDeviceLayer.h>

// Helper macros for creating Erlang terms
#define ATOM(env, name) enif_make_atom(env, name)
#define OK(env) ATOM(env, "ok")
#define ERROR(env) ATOM(env, "error")
#define OK_TUPLE(env, term) enif_make_tuple2(env, OK(env), term)
#define ERROR_TUPLE(env, reason) enif_make_tuple2(env, ERROR(env), ATOM(env, reason))

// Resource type for Matter context (will hold Matter SDK state)
static ErlNifResourceType* MATTER_CONTEXT_RESOURCE = nullptr;

typedef struct {
    bool initialized;
    // TODO: Add Matter SDK context objects here
    // chip::DeviceLayer::PlatformManager* platform_mgr;
    // chip::Server* server;
} MatterContext;

/**
 * Resource destructor - called when the Erlang term is garbage collected
 */
static void matter_context_destructor(ErlNifEnv* env, void* obj) {
    MatterContext* ctx = static_cast<MatterContext*>(obj);
    if (ctx && ctx->initialized) {
        // TODO: Cleanup Matter SDK resources
        // chip::Server::GetInstance().Shutdown();
        // chip::DeviceLayer::PlatformMgr().Shutdown();
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

    // TODO: Initialize Matter SDK
    // CHIP_ERROR err = chip::DeviceLayer::PlatformMgr().InitChipStack();
    // if (err != CHIP_NO_ERROR) {
    //     enif_release_resource(ctx);
    //     return ERROR_TUPLE(env, "chip_init_failed");
    // }

    // For now, just mark as initialized (stub implementation)
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

    // TODO: Start Matter server
    // chip::Server::GetInstance().Init();
    // chip::DeviceLayer::PlatformMgr().StartEventLoopTask();

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

    // TODO: Stop Matter server
    // chip::Server::GetInstance().Shutdown();

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

    // TODO: Implement attribute setting via Matter SDK
    // This will need to map to the appropriate cluster and update the attribute

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

    // TODO: Implement attribute getting via Matter SDK
    // For now, return a placeholder
    return OK_TUPLE(env, enif_make_int(env, 0));
}

// NIF function table
static ErlNifFunc nif_funcs[] = {
    {"nif_init", 0, nif_init, 0},
    {"nif_start_server", 1, nif_start_server, 0},
    {"nif_stop_server", 1, nif_stop_server, 0},
    {"nif_get_info", 1, nif_get_info, 0},
    {"nif_set_attribute", 5, nif_set_attribute, 0},
    {"nif_get_attribute", 4, nif_get_attribute, 0},
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
ERL_NIF_INIT(Elixir.MatterNerves.Matter.NIF, nif_funcs, nif_load, nullptr, nif_upgrade, nullptr)
