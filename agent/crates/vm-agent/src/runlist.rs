//! runlist.rs — what RUN may launch, read once at startup.
//!
//! The list is the layer's own: the build writes it from the manifest's
//! `run` into `/etc/katmate/run-whitelist` (ADR-043 §5), one binary name
//! per line, each line ending in a newline, no comments, no blank lines.
//! The host checks the same list from the layer's T2 meta and is the
//! authority; this copy is the guest's own check, inside the guest's
//! trust domain.
//!
//! A file that is missing, unreadable or malformed is not an error that
//! stops the agent: PING and SHUTDOWN still work, and every RUN is
//! refused. The whole file is rejected on any bad line, rather than the
//! good lines kept, so that a damaged list never runs a subset nobody
//! wrote.

use std::io::Read;

/// Where the build writes the layer's RUN list (ADR-043 §5).
pub const RUN_WHITELIST_PATH: &str = "/etc/katmate/run-whitelist";

/// Upper bound on the file; a list is a handful of names.
const MAX_BYTES: u64 = 64 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunList {
    Loaded(Vec<String>),
    /// Every RUN is refused; the reason is logged once at startup.
    Unavailable(String),
}

impl RunList {
    pub fn load(path: &str) -> RunList {
        let file = match std::fs::File::open(path) {
            Ok(f) => f,
            Err(e) => return RunList::Unavailable(format!("{path}: {e}")),
        };
        let mut bytes = Vec::new();
        if let Err(e) = file.take(MAX_BYTES + 1).read_to_end(&mut bytes) {
            return RunList::Unavailable(format!("{path}: {e}"));
        }
        if bytes.len() as u64 > MAX_BYTES {
            return RunList::Unavailable(format!("{path}: larger than {MAX_BYTES} bytes"));
        }
        match RunList::parse(&bytes) {
            RunList::Unavailable(why) => RunList::Unavailable(format!("{path}: {why}")),
            loaded => loaded,
        }
    }

    pub fn parse(bytes: &[u8]) -> RunList {
        let text = match std::str::from_utf8(bytes) {
            Ok(t) => t,
            Err(_) => return RunList::Unavailable("not UTF-8".into()),
        };
        let Some(body) = text.strip_suffix('\n') else {
            return RunList::Unavailable("empty, or the last line has no newline".into());
        };
        let mut names: Vec<String> = Vec::new();
        for (i, line) in body.split('\n').enumerate() {
            if !valid_name(line) {
                return RunList::Unavailable(format!(
                    "line {}: {line:?} is not a name matching ^[a-z0-9][a-z0-9+.-]*$",
                    i + 1
                ));
            }
            if names.iter().any(|n| n == line) {
                return RunList::Unavailable(format!("line {}: {line:?} is listed twice", i + 1));
            }
            names.push(line.to_string());
        }
        RunList::Loaded(names)
    }

    pub fn allows(&self, app: &str) -> bool {
        match self {
            RunList::Loaded(names) => names.iter().any(|n| n == app),
            RunList::Unavailable(_) => false,
        }
    }
}

/// The package-name pattern the host uses for `run` (cu2 ruling D5).
fn valid_name(s: &str) -> bool {
    let b = s.as_bytes();
    let head = |c: u8| c.is_ascii_lowercase() || c.is_ascii_digit();
    !b.is_empty() && head(b[0]) && b[1..].iter().all(|&c| head(c) || matches!(c, b'+' | b'.' | b'-'))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn loaded(names: &[&str]) -> RunList {
        RunList::Loaded(names.iter().map(|s| s.to_string()).collect())
    }

    #[test]
    fn a_list_as_the_build_writes_it() {
        assert_eq!(
            RunList::parse(b"firefox-esr\nfoot\npcmanfm\n"),
            loaded(&["firefox-esr", "foot", "pcmanfm"])
        );
        assert_eq!(RunList::parse(b"libreoffice\n"), loaded(&["libreoffice"]));
    }

    #[test]
    fn a_malformed_list_refuses_everything() {
        for bad in [
            &b""[..],
            b"\n",
            b"foot",
            b"foot\n\n",
            b"\nfoot\n",
            b"# list\nfoot\n",
            b"foot # terminal\n",
            b"foot\r\n",
            b"Foot\n",
            b"../foot\n",
            b"foot\nfoot\n",
            b" foot\n",
            b"\xff\n",
        ] {
            assert!(
                matches!(RunList::parse(bad), RunList::Unavailable(_)),
                "accepted {bad:?}"
            );
        }
    }

    #[test]
    fn allows_is_an_exact_match() {
        let l = loaded(&["foot", "firefox-esr"]);
        assert!(l.allows("foot"));
        assert!(l.allows("firefox-esr"));
        assert!(!l.allows("firefox"));
        assert!(!l.allows("foot "));
        assert!(!l.allows(""));
        assert!(!RunList::Unavailable("x".into()).allows("foot"));
    }

    #[test]
    fn a_missing_file_is_unavailable() {
        let path = std::env::temp_dir().join(format!("km-runlist-absent-{}", std::process::id()));
        let got = RunList::load(path.to_str().unwrap());
        assert!(matches!(&got, RunList::Unavailable(why) if why.contains("No such file")), "{got:?}");
    }

    #[test]
    fn a_file_is_read_and_an_oversized_one_refused() {
        let dir = std::env::temp_dir();
        let ok = dir.join(format!("km-runlist-ok-{}", std::process::id()));
        std::fs::write(&ok, b"foot\npcmanfm\n").unwrap();
        assert_eq!(RunList::load(ok.to_str().unwrap()), loaded(&["foot", "pcmanfm"]));
        std::fs::remove_file(&ok).unwrap();

        let big = dir.join(format!("km-runlist-big-{}", std::process::id()));
        std::fs::write(&big, "a\n".repeat(MAX_BYTES as usize)).unwrap();
        let got = RunList::load(big.to_str().unwrap());
        std::fs::remove_file(&big).unwrap();
        assert!(matches!(&got, RunList::Unavailable(why) if why.contains("larger than")), "{got:?}");
    }
}
