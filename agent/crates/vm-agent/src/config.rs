//! config.rs — runtime configuration, resolved once at startup.
//!
//! This module reads CONTROL_PORT, HOST_CID and VSOCK_PORT from the
//! agent's environment, falling back to the source-of-truth defaults.
//! The agent's environment is katmate-init's, which sets none of them
//! today, so the defaults are what runs. Invalid values fall back to the default
//! rather than aborting, and (in debug builds) say so.
//!
//! Moved from `agent/src/config.rs`, unchanged in behaviour. Only the
//! fallback SOURCES are re-pointed after the workspace split:
//!
//!   DEFAULT_CONTROL_PORT -> katmate_protocol::frame   (shared: both agents
//!                                                      listen, client dials)
//!   DEFAULT_HOST_CID     -> crate::DEFAULT_HOST_CID     (waypipe policy, local)
//!   DEFAULT_WAYPIPE_PORT -> crate::DEFAULT_WAYPIPE_PORT (waypipe policy, local)
//!
//! netvm-agent has NO config.rs: it takes no waypipe target, and its
//! control port is the shared default. If it ever needs one, it gets its
//! own.

use katmate_protocol::frame;

use crate::{DEFAULT_HOST_CID, DEFAULT_WAYPIPE_PORT};

/// Resolved configuration for one agent run.
#[derive(Debug, Clone, Copy)]
pub struct Config {
    /// VSOCK port the control channel listens on.
    pub control_port: u32,
    /// Host CID (used when composing the waypipe --socket argument).
    pub host_cid: u32,
    /// VSOCK port waypipe uses for the GUI channel.
    pub waypipe_port: u32,
}

impl Config {
    /// Resolve configuration from the environment, with defaults.
    pub fn from_env() -> Config {
        Config {
            // The unit's VSOCK_PORT names the waypipe GUI port (1024),
            // not the control port. The control port is the agent's own
            // listen port and stays on its default unless explicitly
            // overridden via CONTROL_PORT.
            control_port: env_u32("CONTROL_PORT", frame::DEFAULT_CONTROL_PORT),
            host_cid: env_u32("HOST_CID", DEFAULT_HOST_CID),
            waypipe_port: env_u32("VSOCK_PORT", DEFAULT_WAYPIPE_PORT),
        }
    }
}

/// Read a u32 environment variable, falling back to `default` if the
/// variable is unset or unparseable.
fn env_u32(key: &str, default: u32) -> u32 {
    match std::env::var(key) {
        Ok(raw) => match raw.trim().parse::<u32>() {
            Ok(v) => v,
            Err(_) => {
                crate::log_debug!("env {key}={raw:?} is not a u32; using default {default}");
                default
            }
        },
        Err(_) => default,
    }
}
