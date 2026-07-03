# Waypipe patch queue

KatMate maintains waypipe as a *patch-queue fork* ("fork lite", ADR-019):
one pinned upstream tag plus a small, ordered queue of patches applied on
top. Both host and guest waypipe binaries are built from this same tree.

## Pinned upstream

- Tag: `v0.11.0`
- Patch level: 0 (queue currently empty)

The pin (tag + patch level) is the single project-wide waypipe version,
recorded in `/var/lib/katmate/foundation.meta` at foundation RO-freeze time.

## Scope: strip and harden only

Patches in this queue MUST only remove or compile out code paths the trust
boundary must not carry, beyond what meson feature flags already disable:

- ssh transport mode
- video encoding
- dmabuf / gbm paths
- reconnect logic

The vsock path is the only entry point that must remain. No feature
development, no divergence from upstream's core. Wayland protocol evolution
stays upstream's responsibility.

## Application order

Patches are applied in ascending filename order:

    NNNN-short-description.patch

where `NNNN` is a zero-padded sequence number starting at `0001`. The build
scripts (`build/waypipe-host.sh` for the host, the foundation chroot recipe
for the guest) apply every `*.patch` in this directory, in order, with
`patch -p1`. A patch that fails to apply is a hard build error.

## Adding a patch

1. Modify the checked-out pinned tree.
2. Generate the patch: `git diff > NNNN-short-description.patch`.
3. Commit the patch file here; bump the patch level in this README and in
   the build metadata writer.
4. Rebuild both binaries from the same tree; version-lock enforcement at
   launch rejects any mismatch.
