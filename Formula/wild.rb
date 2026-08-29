# Homebrew formula for `wild` — the source the tap is rendered from.
#
# This file is the SOURCE of the Wild brew formula. The install path is
# `wildstuff/homebrew-tap` (a separate repo), and its `Formula/wild.rb` is
# DERIVED from this one: on every release tag `release.yml` runs
# `scripts/ci/render-brew-formula.py` over this file, filling each `url` +
# `sha256` in from the tag and the checksums the build just wrote, and
# opens the resulting formula as a pull request on the tap.
#
# So this is the only copy anyone edits. It was hand-mirrored into the tap
# until #5145, where every cut from v0.5.0-rc.2 on failed its bump and the
# tap was moved by hand — a second hand-maintained copy of anything is a
# copy that drifts, and this one drifted two releases behind.
#
# The version pinned in the URLs below is a SPECIMEN, not state: the render
# overwrites every one of them. It stays a real, resolvable release so the
# file loads, audits and reads honestly on its own.
#
# URLs point at the PUBLIC distribution repo `wildstuff/wild`
# (ADR-0225 D2): release assets inherit repo visibility, and the
# development repo `the-wild` stays private by decision, so any URL
# naming it 404s for the tap's audience.
#
# Layout:
#   - Tarball is downloaded from the GitHub Release matching the
#     formula's version. The release ships pre-built binaries +
#     `dist/{launchd,systemd,install}/` + `docs/operator-daemon.md`
#     (ADR-0035 §3.3.4.B).
#   - `install` lays both binaries into `bin/`, the daemon-init
#     templates + install helpers into `share/wild/`, and the
#     migration guide into `share/doc/wild/`.
#   - `brew install --HEAD` builds both binaries from develop instead
#     (the source-build path folded in from the retired top-level
#     `homebrew/wild.rb`); see the `head` block + `build.head?` branch.
#     INSIDERS ONLY — the clone needs read access to the private
#     development repo.
#   - `service do … end` block teaches `brew services start wild` to
#     run `wild-hostd` as a LaunchAgent — operators don't need to
#     touch `dist/install/install-launchd.sh` for the brew install
#     path; the helper stays useful for source / cargo installs.

class Wild < Formula
  desc "Tribe orchestrator — terminal-first interface + headless runtime daemon"
  homepage "https://github.com/wildstuff/wild"
  license "FSL-1.1-ALv2"

  # The DEFAULT tarball. Homebrew requires a stable `url` at this level, and
  # every platform we publish for overrides it in an `on_*` block below.
  # Nothing is meant to reach this line: the one platform that would —
  # Intel macOS — is refused outright by the `depends_on arch:` in the
  # `on_macos` block, because falling through to it silently installs Apple
  # Silicon binaries on a machine that cannot run them.
  #
  # Keep `url` and `sha256` as adjacent, simple, one-line stanzas wherever
  # they appear: `render-brew-formula.py` pairs each url with the `sha256`
  # DIRECTLY beneath it, and that adjacency is what stops a platform from
  # inheriting another platform's checksum.
  #
  # NO `version` stanza, here or in any block. The URL carries the version
  # and Homebrew derives it from there; a redundant stanza beside a derived
  # value does not merely duplicate, it OUTRANKS — the moment the two
  # disagree, the stale one wins and the formula pins itself.
  url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.9/wild-0.5.0-rc.9-aarch64-apple-darwin.tar.gz"
  sha256   "bb1b9c42d1c196efbaf74d61e11db2ea26dd464555f1b2c1fd9fadc131c4860b"

  # Runtime, not build: wild-hostd execs nats-server from PATH unless a
  # bundled/downloaded one is found (ADR-0120 D11 bundles it into the
  # .app; the tarball relies on this dep).
  depends_on "nats-server"

  # `brew install --HEAD wildstuff/tap/wild` builds the current develop
  # tip from source instead of a release tarball. Folded in from the
  # retired top-level `homebrew/wild.rb` (the pre-release source-build
  # formula) so one formula covers both the binary and source paths.
  # INSIDER PATH: the clone needs read access to the private repo — the
  # public tree (ADR-0225 D1) carries no crates to build from.
  head "https://github.com/wildstuff/the-wild.git", branch: "develop"
  head do
    # Source build needs the Rust toolchain + wasm32-wasip1 target
    # (cargo-component emits the chief wasm against it); the stable
    # binary-tarball path needs neither.
    depends_on "rust" => :build
  end

  # Per-platform asset selection. Brew's `on_*` macros rewrite
  # `url`/`sha256` to the matching tarball at install time, and there must
  # be one block per target in `release.yml`'s build matrix — a missing one
  # does not fail, it silently falls through to the default url above and
  # hands that platform another platform's binaries. `wild-release-version`
  # holds the test that keeps the two lists equal.
  #
  # These blocks are also why `brew bump-formula-pr` cannot maintain this
  # formula and why we render it ourselves; the whole measurement is in
  # `scripts/ci/render-brew-formula.py`.
  on_macos do
    on_arm do
      url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.9/wild-0.5.0-rc.9-aarch64-apple-darwin.tar.gz"
      sha256   "bb1b9c42d1c196efbaf74d61e11db2ea26dd464555f1b2c1fd9fadc131c4860b"
    end
    # Intel macOS is NOT a supported target. It left the release matrix on
    # 2026-05-05 — Apple stopped selling Intel Macs in late 2023 and macOS
    # runners bill at ten times the rate — and nothing has been published
    # for it since.
    #
    # This line is what makes that a REFUSAL rather than a wrong install.
    # Without it an Intel Mac matches no block, falls through to the
    # default `url` at the top of the formula, and unpacks the Apple
    # Silicon tarball: two arm64 Mach-O binaries, no error until the first
    # exec. `install.sh` already refuses an Intel Mac up front, in as many
    # words; the brew door was the one that did not.
    #
    # Homebrew's own message is generic ("The arm64 architecture is
    # required for this software"), so the way out is stated here for
    # whoever reads the formula: build from source with
    # `brew install --HEAD wildstuff/tap/wild`, or
    # `cargo install --path crates/runtime/frontend` (+ `.../daemon`).
    depends_on arch: :arm64
  end

  on_linux do
    on_intel do
      url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.9/wild-0.5.0-rc.9-x86_64-unknown-linux-gnu.tar.gz"
      sha256   "db858f6ce642a56b478a2d1352d79e283bf49400d3c7b8d6c0914620cd3113e4"
    end
    # ARM servers are a release target since 2026-08-11 and had no block
    # here, so `brew install` on an arm64 Linux box fell through to the
    # default url and unpacked the MACOS tarball — two Mach-O binaries with
    # no error until the first exec.
    on_arm do
      url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.9/wild-0.5.0-rc.9-aarch64-unknown-linux-gnu.tar.gz"
      sha256   "599eaba364b1c7012f9c767c5692e3ea323bfd82c3bf86307dec039f0458044a"
    end
  end

  def install
    if build.head?
      # Source build (`brew install --HEAD`). Slower (~3-5 min: pulls
      # the Rust toolchain + cargo-component + wkg) but zero release-
      # pipeline coupling — builds straight from develop.
      ENV["CARGO_HOME"] = buildpath/".cargo"

      # cargo-component emits the chief wasm against wasm32-wasip1;
      # daemon/build.rs then include_bytes!s the bundled result.
      system "rustup", "target", "add", "wasm32-wasip1"

      # Build tools xtask invokes — pinned, installed onto PATH up front.
      system "cargo", "install", "--locked", "--root", buildpath/".cargo",
             "cargo-component", "--version", "^0.18"
      system "cargo", "install", "--locked", "--root", buildpath/".cargo",
             "wkg", "--version", "^0.7"
      ENV.prepend_path "PATH", buildpath/".cargo/bin"

      # Restore wit/external/ packages (idempotent), then bake the
      # Tier-1.5 default chief into dist/embedded/ — order matters, the
      # daemon build include_bytes!s it.
      system "cargo", "run", "-p", "xtask", "--release", "--", "wit-sync"
      system "cargo", "run", "-p", "xtask", "--release", "--", "bundle-chief"

      # Both binaries: `wild` (frontend) + `wild-hostd` (daemon). Post
      # ADR-0036 they're separate crates under crates/runtime/.
      system "cargo", "install", *std_cargo_args(path: "crates/runtime/frontend")
      system "cargo", "install", *std_cargo_args(path: "crates/runtime/daemon")
    else
      # Pre-built tarball (stable) — ADR-0035 §3.3.4. Both binaries
      # ship as separate executables: `wild` is the frontend cli
      # (chat / status / metrics / etc.); `wild-hostd` is the long-
      # running daemon `brew services` wraps.
      bin.install "wild"
      bin.install "wild-hostd"
    end

    # Init-script templates land under `share/wild/dist/` so they're
    # discoverable via `brew --prefix wild`; operator guide under
    # `share/doc/wild/`. Present in both the release tarball and the
    # source checkout, so this runs for both variants.
    (share/"wild/dist").install Dir["dist/*"]
    (share/"doc/wild").install Dir["docs/*"]
  end

  # `brew services start wild` — turns wild-hostd into a managed
  # LaunchAgent (macOS) or systemd-user service (Linux) without the
  # operator needing to run our `install-launchd.sh` helper. Brew
  # generates the plist/unit on the fly using these fields.
  #
  # Stopping: `brew services stop wild` (clean shutdown — wild-hostd
  # exits cleanly on SIGTERM via its existing handler).
  service do
    run [opt_bin/"wild-hostd"]
    keep_alive true
    log_path   var/"log/wild-hostd.log"
    error_log_path var/"log/wild-hostd.err.log"
    # Don't fight with a manual `wild up` on the same profile. The
    # IPC daemon-already-running probe (ADR-0035 §3.3.2.B) surfaces
    # the conflict in <1 s; brew services doesn't need to gate.
  end

  test do
    # Smoke test — both binaries should print `--version` without a
    # daemon up. Keeps the formula honest if a future build accidentally
    # hard-fails on a missing profile root.
    assert_match version.to_s, shell_output("#{bin}/wild --version")
    assert_match version.to_s, shell_output("#{bin}/wild-hostd --version")
  end

  def caveats
    <<~EOS
      Wild ships two binaries:
        - `wild`        the frontend cli (chat / status / metrics / reconcile / log-level / debug / …)
        - `wild-hostd`  the long-running runtime daemon

      Pick ONE of these to run the daemon (mixing them races the
      IPC control socket — the §3.3.2.B probe will catch this with
      a clear "daemon already running" error, but you'll have to
      pick anyway):

        # 1. brew-managed service (recommended for long-running setups)
        brew services start wild
        wild status                       # smoke-test the daemon

        # 2. interactive `wild up` (laptops, demos)
        wild up                           # in-process; exits with the TUI

      Profile state lives under Wild's data root:
      ~/Library/Application Support/Wild/profiles/<active>/ on macOS,
      ~/.local/share/wild/profiles/<active>/ on Linux. The brew
      service uses your active profile by default; pin a different
      one by exporting WILD_PROFILE=<name> via
      `~/Library/LaunchAgents/homebrew.mxcl.wild.plist` (macOS) or
      a systemd drop-in (Linux).

      Operator guide:
        less #{share}/doc/wild/operator-daemon.md
    EOS
  end
end
