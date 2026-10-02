# CLAUDE.md — standing context for delegated sessions

KatMate OS: a compartmentalized desktop OS — QEMU/KVM MicroVMs on a hardened
Arch host, Debian guests, AF_VSOCK as the only host↔guest channel. Milestone
v0.2, single developer, pre-alpha. `README.md` is the orientation; this file is
the working contract.

## What this file is

Standing context for a delegated agent session in this repository. It is loaded
automatically; the per-session **brief** is not. The division:

- **This file** — what is always true: machine roles, hard constraints, reading
  order, report contract. **It never contains a task.**
- **The brief** (`~/<step>-brief.md`, untracked) — what this session is to do.
- **The report** (`~/<step>-report.md`, untracked) — what it did, and where the
  brief was wrong.

**This file routes; it does not restate.** Every fact in this project lives in
exactly one document (`README.md`, *Maintenance rules*). An ADR paraphrased here
would be a second source that drifts — this project's characteristic failure
class, the same shape as a stale BDF or a `networkctl` reporting `routable` and
`offline` together. Where something is stated inline below, it is because the
session must know it *before* it has read anything, not because it matters more.

## The two machines

| | **Acer** (`winterbox`, N4200) | **MINIS** (UM870, Ryzen 7 8745H) |
|---|---|---|
| Role | git source of truth | build + runtime host |
| Tree | `~/katmate-os/` — the repository | `~/katmate-build/` — a synced copy |
| Git / GPG | all commits, all signing | **none, ever** |
| KatMate installed | no | yes — the only live system |
| Build scripts | cannot run: no root LVM, no `vg0`, no thin pool, no `debootstrap` | yes |
| Gates | cannot run | the only place a gate means anything |

**Sync is one-way: Acer → MINIS, `rsync --delete`.** An edit to a tracked file
made on MINIS is removed at the next sync, without a diagnostic.

**Reaching MINIS is not `ssh 10.3.1.3`, and the shell that answers does not run
sh.** The account, the key, and how a bash or sh snippet has to be delivered are
in `state.md` § *Live state*, under *Dev access to MINIS*. A brief that hands you
an `ssh <ip> '…'` one-liner for MINIS is wrong on both counts; read that entry
before you issue the first remote command, whatever the brief says.

**The Acer is not a KatMate host.** It runs no VMs; none of `/etc/katmate`,
`/var/lib/katmate`, `/opt/katmate` exists on it, and `sudo -n` needs a password.
Anything an Acer session produces that belongs at a canonical path is a
**reviewable artefact and a fixture, not live configuration**, and the report
must say so in those words.

Identity for every commit: `KatMate <git@katmate-os.org>`, GPG-signed (`-S`),
key `3F49AE514562ACD3FF9D6049F8841B7B3D3AB436`. Remote
`codeberg.org:KatMate/katmate-os.git`, branch `main`. The `pages` branch is
Codeberg Pages — never project work.

## Reading order, before the first change

1. **`state.md`** — current focus, the two most recent sessions, live state,
   open problems, next steps, and **§ *Invariants & gotchas* in full**. Volatile
   by design, and also where the traps that cost a host reboot are written down.
2. **The brief.**
3. **The ADRs the brief names**, in `docs/DECISIONS.md` — including their
   **revision notes**. Several ADRs have been corrected by later ones, and the
   note *is* the correction; an ADR read without its notes will be read wrong.
4. **The files the brief touches.** Read them. Do not infer a file's contents
   from an ADR that describes it. Where the tree is the subject, the tree has to
   be read — every wrong assertion this project has recorded came from reasoning
   over a description instead of the thing.

   **A grep pattern containing `$` needs `grep -F`, or the `$` escaped.** A `$`
   in mid-pattern is an anchor in a BRE, so that branch is silently
   unsatisfiable: a search for `case "$DERIVED"` reported the marker absent
   while the line was present on HEAD. Only that one alternative of the pattern
   was affected — the others matched — so the search read as partially
   successful rather than as broken. It belongs here and not in a session entry
   because it produces a false negative in exactly the read this list exists to
   make: the one that is supposed to stop the tree being asserted from memory.

`docs/ARCHITECTURE.md` and `docs/SECURITY-MODEL.md` are the frame.
`ROADMAP.md` § *Build order* says which step this is and what it gates.

## Halt before the first change

The read pass ends one of two ways: nothing is wrong, or a numbered list of
divergences goes to the operator and **the session stops there**. It does not
resolve them, and it does not proceed with the part it believes is unaffected.

A divergence is any of: the brief describes the tree wrongly; two documents
disagree; an ADR and the tree disagree; a path the brief names does not exist;
a mechanism the brief assumes has never been observed.

**A disagreement between a document and the tree is a finding, and it is never
resolved silently in either direction.** The ADRs are not automatically right —
step 3a found ADR-030's gate G2 misnamed because `app_web.con` carries no
network device at all. The tree is not automatically right either. The operator
rules; the session records the ruling and moves on.

**Permission-classifier refusals** (operator rulings, 2026-09-29 and
2026-10-02). A **refusal** stops *that action*: it is never retried in another
form — a different form of a refused command is evasion, not a workaround.
The session carries on with the work that does not depend on it, names the
refused command and the classifier's reason in the report, and leaves the
action for the operator. A **no-verdict (error)** is an outage, not a refusal:
wait about 30 s and retry the **same** action, up to 5 times, then stop and
report.

**Auto mode is the default, MINIS work included** (operator ruling,
2026-10-02). `~/.claude/settings.json` on the Acer describes MINIS to the
classifier as the operator's trusted dev host. A refusal of a MINIS command is
a finding about those settings, reported as above. **A session never edits
this file**: the classifier refuses it as *Self-Modification*, by design. A
change to `CLAUDE.md` is proposed in the report and committed by the operator.

## What a session may not decide

- **The content of an ADR.** Propose a revision note in the report; do not write
  one into `docs/DECISIONS.md`.
- **Anything in the tier model** (ADR-030, ADR-032): what is T1/T2/T3/T4, where
  it lives, or how the profile is derived. The profile is `f(class, netvm, nic)`
  and there is exactly one path to it. A second path is not a feature.
- **Whether a gate passed.** A gate is passed by observation, quoted verbatim,
  or it is not passed.

**A delegated session is implementation, not architecture.** Architecture
happens in the operator's chat, deliberately separated. A session that finds
itself designing has hit a divergence — halt and report.

Unrequested changes are permitted when they are cheap, loud and **recorded**: a
hard failure added to a preflight is fine, a silently widened rule is not.
Everything the brief did not authorise goes in the report under its own heading,
with the alternatives that were rejected and why.

## Claim discipline

**Never claim what was not run.** The report carries an explicit section naming
what was not executed and is therefore not claimed.

Code written but not executed — rollback paths above all — is marked
**UNVERIFIED**, with where it first executes and which pair of observations
would settle it.

`bash -n`, `fish -n` and `shellcheck` are static checks and are not evidence of
behaviour. Name which one was run.

## Report contract

Written incrementally, from the first action onward, never reconstructed at the
end. In this order:

1. **What changed, file by file** — with the reasoning, and for each non-obvious
   choice the alternative that was rejected.
2. **Verbatim command output** — commits with `%G?`, static checks, behavioural
   checks. Pasted, not summarised.
3. **Artefacts produced outside the repository, in full.** T1 files and anything
   else untracked by design exist for review only here.
4. **Decisions this brief did not authorise.**
5. **Where this brief is wrong** — divergences found *during* the work, distinct
   from the pre-work list already resolved.
6. **What the next session must know** — including every published statement
   this session contradicts, named by document and section.

## Commits

One concern per commit. GPG-signed. The message states the reasoning, not the
diff. `git rm`, never `rm`, on a tracked path — and check `git ls-files <path>`,
not `find`, for what is actually tracked. Never `git add -A`, and never stage a
file this session did not write: the operator edits the tree concurrently, and
an unstaged modification in `git status` is usually his.

## Language

Everything in the repository is **en_US** — code, comments, diagnostics, commit
messages, documentation (decided 2026-08-09).

**A delegated session writes en_US throughout — its chat output and its report
included.** The Slovenian working dialogue is the operator's own chat, not this
one. A report is the input from which en_US repository content is written, so a
Slovenian report inserts a translation step between the measurement and the
record, and translation is where wording drifts.

`tools/validate-properties.fish` and `bin/katmate-cid` are still Slovenian; that
translation is a named open item and its own commit, not something to do in
passing.

## Running things

- Pipe diagnostics through `| cat`. fish's pager makes a stray `q`
  indistinguishable from end of output.
- Build and pipeline scripts are bash (`#!/usr/bin/env bash`); the interactive
  shell is fish. `app_web.con` stays fish deliberately.
- `micro` strips the executable bit on save — `chmod +x` before `git add`, not
  `git update-index --chmod=+x` after.
- Never rsync or copy a kernel build tree with broad `--exclude` patterns:
  `--exclude='vmlinux.*'` eats the source `vmlinux.lds.S`.

## On MINIS: what a mistake costs

MINIS holds no valuable data. It holds the only **live state** in the project,
and that state is the instrument every gate is measured with. The cost of a
mistake is a rebuild cycle and a lost measurement — which, under a methodology
of empirics-before-commitment, is the expensive thing.

| Mistake | Cost |
|---|---|
| Editing a tracked file on MINIS | removed at the next `rsync --delete`, silently |
| Committing on MINIS | divergent history; git exists only on the Acer |
| Running `build/netvm.sh` without a reboot since the last one | `jbd2` holds the LV open after **every** build, successful or failed (measured 2026-09-03 and 2026-09-05, on two different boots); `sync` / `udevadm settle` / `dmsetup` do not clear it — **host reboot**, and `lvremove` fails until then. Reboot **before** each build, not after a failure |
| Forcing `lvremove` on a hot LV | do not. Reboot first |
| Killing the QEMU on CID 3 | the machine loses its uplink |
| Suspend during a netVM build | the jbd2 case above. Mask `sleep.target suspend.target hibernate.target hybrid-sleep.target` first; unmask after |
| Booting an instance without `lvchange -K -ay` | RO-frozen thin LVs keep the skip-activation `k` flag permanently; the device node is absent and QEMU fails quietly |
| Trusting a fast `Finished` after an rsync | rsync preserves mtime, so cargo skips the rebuild and you are testing the old binary. Confirm with `strings <bin> \| grep` |

`state.md` § *Invariants & gotchas* carries these with their diagnoses, and
roughly twenty more. It is not background reading.

## Ask before, unless the brief names it explicitly

- Any `lvremove`, `lvchange`, `dmsetup`, `mkfs`, or `qemu-img create` outside a
  build script the brief names.
- Starting or stopping netVM (CID 3), or anything holding a passed-through NIC.
- `git push`, `git rebase`, `git reset --hard`, or any force operation.
- Writing under `/etc/katmate/`, `/var/lib/katmate/`, `/opt/katmate/`,
  `/usr/lib/katmate/`. These are the tier directories: what is written there is
  a claim about tier, and the installer may create a T1 file but may never
  overwrite one it did not create in the same run.
- Anything a host reboot would be needed to undo.
