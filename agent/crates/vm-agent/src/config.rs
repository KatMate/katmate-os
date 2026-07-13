//! config.rs — appVM agent runtime config (CONTROL_PORT / HOST_CID /
//! VSOCK_PORT, exported by the systemd --user unit).
//!
//! CODE SESSION: MOVE of `agent/src/config.rs`, unchanged in behaviour. Only
//! the fallback sources are re-pointed after the split:
//!
//!   DEFAULT_CONTROL_PORT -> katmate_protocol::frame  (shared: both agents
//!                                                     listen, client dials)
//!   DEFAULT_HOST_CID     -> local constant in main.rs (waypipe policy)
//!   DEFAULT_WAYPIPE_PORT -> local constant in main.rs (waypipe policy)
//!
//! netvm-agent has NO config.rs: it takes no waypipe target, and its control
//! port is the shared default. If it ever needs one, it gets its own.
