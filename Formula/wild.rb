# Homebrew formula for `wild` — in-repo snapshot.
#
# This file is the source of truth for the Wild brew formula. The
# actual install path is `wildstuff/homebrew-tap` (a separate repo);
# `release.yml`'s `dawidd6/action-homebrew-bump-formula` step pushes
# version + sha256 updates over there on every release tag, but the
# Ruby class shape itself lives here so reviews + history land in
# the same place as the rest of the codebase.
#
# When this file changes, copy the result into the tap repo's
# `Formula/wild.rb`. Future iteration can teach the bump-action to
# template from this file too; for now the action only updates the
# `url` + `sha256` attributes.
#
# URLs point at the PUBLIC distribution repo `wildstuff/wild`
# (ADR-0225 D2): release assets inherit repo visibility, and the
# development repo `the-wild` stays private by decision, so any URL
# naming it 404s for the tap's audience. The bump-action's version
# substitution + anonymous sha256 download only work against the
# public repo.
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

  # Both attributes are auto-bumped by `dawidd6/action-homebrew-bump-formula`
  # on every release. Keep them as simple `url`/`sha256` lines so the
  # action's regex parser finds them.
  url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.5/wild-0.5.0-rc.5-aarch64-apple-darwin.tar.gz"
  sha256   "c3d0979372c45aa038fee270f3a5cba5b36249ac235ccb23b787bb931669ba5a"
  version  "0.5.0-rc.5"

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

  # Per-architecture asset selection. Brew's `on_*` macros rewrite
  # `url`/`sha256` to the matching tarball at install time. The
  # bump-action populates each block on release.
  on_macos do
    on_arm do
      url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.5/wild-0.5.0-rc.5-aarch64-apple-darwin.tar.gz"
      sha256   "c3d0979372c45aa038fee270f3a5cba5b36249ac235ccb23b787bb931669ba5a"
    end
    # Intel macOS dropped from the release matrix 2026-05-05 (per
    # `release.yml`'s comment block). Operators on Intel Macs build
    # from source via `brew install --HEAD wildstuff/tap/wild` or
    # `cargo install --path crates/runtime/cli`.
  end

  on_linux do
    on_intel do
      url      "https://github.com/wildstuff/wild/releases/download/v0.5.0-rc.5/wild-0.5.0-rc.5-x86_64-unknown-linux-gnu.tar.gz"
      sha256   "9a934fed3007af0b5993be76766e5442b78a503cfaf4b57129a4c9360a14f325"
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
    # hard-fails on a missing `~/.wild/`.
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

      Profile state lives at ~/.wild/profiles/<active>/. The brew
      service uses your active profile by default; pin a different
      one by exporting WILD_PROFILE=<name> via
      `~/Library/LaunchAgents/homebrew.mxcl.wild.plist` (macOS) or
      a systemd drop-in (Linux).

      Operator guide:
        less #{share}/doc/wild/operator-daemon.md
    EOS
  end
end
