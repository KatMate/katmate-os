//! config.rs — runtime configuration, resolved once at startup.
//!
//! The systemd unit exports VSOCK_PORT, HOST_CID and VM_CID into the
//! agent's environment. This module reads them, falling back to the
//! source-of-truth defaults in `protocol`. Invalid values fall back to
//! the default rather than aborting, and (in debug builds) say so.

use crate::protocol;

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
            control_port: env_u32("CONTROL_PORT", protocol::DEFAULT_CONTROL_PORT),
            host_cid: env_u32("HOST_CID", protocol::DEFAULT_HOST_CID),
            waypipe_port: env_u32("VSOCK_PORT", protocol::DEFAULT_WAYPIPE_PORT),
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
