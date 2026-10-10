# How AI is used in this project

## Whose design this is

The architecture, the security model, the vsock control protocol, the QEMU
launchers and the routed netVM are mine; I brought them into this project.
Every architectural decision is mine. Each is recorded as an ADR in
[docs/DECISIONS.md](docs/DECISIONS.md) or as a numbered ruling.

## Why AI

After 40 years of systems engineering and coding, I currently trust a good
coding model working under my supervision more than a human developer to
implement my architecture. AI is essential here, for development, for testing
and for documentation.

## What the AI does

- It writes code to my specifications.
- It drafts ADRs and session briefs from my rulings. The text may be the
  model's; the design, architecture and decisions in it are mine.
- It runs measurements on my hardware, under my supervision.
- It writes and audits documentation.

## How it is controlled

The working contract is [CLAUDE.md](CLAUDE.md); every delegated session reads
it first. In short:

- **One brief per step.** A session works from its own brief, and anything
  it does beyond the brief is reported as such.
- **Halt on divergence.** Before its first change, the agent reads the brief,
  the documents and the tree. Where they disagree, it stops and lists the
  divergences instead of resolving them.
- **I rule on every divergence**, including code design (variables,
  functions, code input/output pipes, code interactions and algorithm logic
  flows). The ruling is numbered and recorded, and the work continues from
  it.
- **Gates are passed by observation only.** An observation is quoted
  verbatim, or the gate is not passed. What was not run is not claimed.
- **Every commit on `main` is reviewed and GPG-signed by me**, with the one
  exception recorded under *Provenance*.

## What else this project is

It is also a demonstration of building and supervising a complex
AI-assisted engineering process for secure systems.
