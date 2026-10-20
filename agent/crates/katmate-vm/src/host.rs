//! Everything `katmate-vm` does outside its own files goes through [`Host`]:
//! LVM, mkfs, mount, qemu-img and the T4 helpers, each by absolute path, and
//! the terminal for `--purge`. The tests replace it with a recording fake.

use std::io::{BufRead, Write};
use std::path::Path;
use std::process::{Command, Stdio};

pub trait Host {
    /// Runs `argv` (argv[0] an absolute path) with stdin closed; its stdout on
    /// exit 0, otherwise a one-line reason.
    fn run(&self, argv: &[&str]) -> Result<String, String>;
    fn stdin_is_tty(&self) -> bool;
    /// Prints `prompt` on stderr and reads one line from stdin, without its
    /// newline.
    fn ask(&self, prompt: &str) -> Result<String, String>;
}

pub struct RealHost;

/// What a failed program said: its FATAL lines (katmate-lib.sh's form), else
/// its last stderr line, else its last stdout line.
pub fn reason(stdout: &str, stderr: &str) -> String {
    let fatal: Vec<&str> = stderr.lines().filter(|l| l.contains("FATAL:")).collect();
    if !fatal.is_empty() {
        return fatal.join(" | ");
    }
    let last = |s: &str| s.lines().rev().find(|l| !l.trim().is_empty()).map(str::trim).map(String::from);
    last(stderr).or_else(|| last(stdout)).unwrap_or_else(|| "no output".to_string())
}

impl Host for RealHost {
    fn run(&self, argv: &[&str]) -> Result<String, String> {
        let (prog, args) = argv.split_first().ok_or("empty command")?;
        let out = Command::new(prog)
            .args(args)
            .env("PATH", "/usr/bin")
            .stdin(Stdio::null())
            .output()
            .map_err(|e| format!("cannot run {prog}: {e}"))?;
        let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
        if out.status.success() {
            return Ok(stdout);
        }
        let name = Path::new(prog).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let code = out.status.code().map_or_else(|| "a signal".to_string(), |c| c.to_string());
        Err(format!("{name} {} exited {code}: {}", args.join(" "), reason(&stdout, &String::from_utf8_lossy(&out.stderr))))
    }

    fn stdin_is_tty(&self) -> bool {
        // SAFETY: isatty on fd 0 has no memory effects.
        unsafe { libc::isatty(0) == 1 }
    }

    fn ask(&self, prompt: &str) -> Result<String, String> {
        eprint!("{prompt}");
        let _ = std::io::stderr().flush();
        let mut line = String::new();
        std::io::stdin().lock().read_line(&mut line).map_err(|e| format!("cannot read stdin: {e}"))?;
        Ok(line.trim_end_matches('\n').to_string())
    }
}
