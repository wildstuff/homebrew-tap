# Homebrew Formula for `wild`.
#
# This file is the canonical source — copy it into the
# `Wildstuff/homebrew-tap` tap repo at `Formula/wild.rb` after
# every wild release. The tap repo is separate from the-wild so
# `brew install wildstuff/tap/wild` resolves correctly without
# Homebrew having to clone the whole monorepo on every brew search.
#
# Variant: source build via `cargo install`. Slower install
# (3-5 minutes; pulls Rust toolchain + cargo-component + wkg) but
# zero release-pipeline coupling — it builds straight from the
# git tag's auto-generated source tarball.
#
# After v0.1.0's release.yml pipeline produces multi-arch
# pre-built tarballs, switch to a binary Formula (the
# `# Pre-built variant` template at the bottom of this file). The
# source-build Formula then becomes the `--HEAD` fallback for
# users who want to build develop.

class Wild < Formula
  desc "Multi-tribe LLM agent runtime"
  homepage "https://github.com/Wildstuff/the-wild"
  url "https://github.com/Wildstuff/the-wild/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"  # `gh release view v0.1.0 --json tarballUrl,publishedAt | jq` then `shasum -a 256 <tarball>`
  license "Apache-2.0"
  head "https://github.com/Wildstuff/the-wild.git", branch: "develop"

  depends_on "rust" => :build
  depends_on "nats-server"

  def install
    # Isolate cargo state so the user's existing toolchain isn't
    # touched and the Formula's repeated installs are deterministic.
    ENV["CARGO_HOME"] = buildpath/".cargo"

    # The wasm32-wasip1 target is required by xtask bundle-chief
    # (cargo-component emits the chief wasm against this target;
    # cli/build.rs then include_bytes!s the result).
    system "rustup", "target", "add", "wasm32-wasip1"

    # Build tools xtask invokes. Pinned via Cargo.toml workspace
    # but the host build needs them on PATH up front.
    system "cargo", "install", "--locked", "--root", buildpath/".cargo",
           "cargo-component", "--version", "^0.18"
    system "cargo", "install", "--locked", "--root", buildpath/".cargo",
           "wkg", "--version", "^0.7"
    ENV.prepend_path "PATH", buildpath/".cargo/bin"

    # Restore wit/external/ packages from the WebAssembly registry.
    # `xtask wit-sync` is idempotent — skips packages whose `.wasm`
    # already exists; we run it unconditionally so a stale checkout
    # isn't silently missing wasi:http etc.
    system "cargo", "run", "-p", "xtask", "--release", "--", "wit-sync"

    # Bake the Tier-1.5 default chief wasm into
    # dist/embedded/chief-default.wasm. cli/build.rs
    # include_bytes!s this on the next compile, so the order matters.
    system "cargo", "run", "-p", "xtask", "--release", "--", "bundle-chief"

    # Build + install the wild binary into Homebrew's bin.
    system "cargo", "install", *std_cargo_args(path: "crates/runtime/cli")
  end

  def caveats
    <<~EOS
      wild ships with the `nats-server` dependency (handled by brew).

      Optional runtime add-ons — install separately if you need them:

        • docker        — for the Forge component build sandbox
                          (`wild plugin add` building components from source).
                          On macOS: brew install --cask docker

        • claude CLI    — for the anthropic-cli LLM adapter.
                          Install per Anthropic's instructions
                          (https://docs.anthropic.com/claude/cli),
                          then `wild plugin grant anthropic-cli wild:cli-exec/exec@0.1.0`.

      First boot: `wild up` pulls every plugin component image from
      ghcr.io/wildstuff (one-time per profile, ~30 MiB). Cached under
      `~/.wild/profiles/<active>/oci-cache/` and digest-pinned in
      `~/.config/wild/bootstrap.lock` for reproducibility.

      Quick start:

        wild up                    # boot the embedded host
        wild doctor                # health snapshot
        wild secret add OPENAI_API_KEY    # store credentials
        wild config llm list       # registered adapters

      Full docs: https://github.com/Wildstuff/the-wild
    EOS
  end

  test do
    # Smoke: binary runs + version string contains the formula version.
    assert_match version.to_s, shell_output("#{bin}/wild --version")
    # Doctor exits cleanly even without NATS reachable (it just
    # marks the row UNREACHABLE) — robust smoke test.
    system "#{bin}/wild", "doctor", "--no-color"
  end
end

# ── Pre-built variant (paste once release tarballs exist) ─────────
#
# After release.yml has pushed `wild-<version>-<target>.tar.gz`
# assets to the GitHub Release for v<version>, swap the body of
# this file for the block below. Multi-arch tarballs install in
# ~5 seconds, no Rust toolchain involved.
#
#   class Wild < Formula
#     desc "Multi-tribe LLM agent runtime"
#     homepage "https://github.com/Wildstuff/the-wild"
#     version "0.1.0"
#     license "Apache-2.0"
#
#     on_macos do
#       on_arm do
#         url "https://github.com/Wildstuff/the-wild/releases/download/v#{version}/wild-#{version}-aarch64-apple-darwin.tar.gz"
#         sha256 "..."
#       end
#       on_intel do
#         url "https://github.com/Wildstuff/the-wild/releases/download/v#{version}/wild-#{version}-x86_64-apple-darwin.tar.gz"
#         sha256 "..."
#       end
#     end
#     on_linux do
#       url "https://github.com/Wildstuff/the-wild/releases/download/v#{version}/wild-#{version}-x86_64-unknown-linux-gnu.tar.gz"
#       sha256 "..."
#     end
#
#     depends_on "nats-server"
#     # Drop the `rust => :build` dep — pre-built binaries don't need it.
#
#     def install
#       bin.install "wild"
#     end
#
#     # caveats + test stay the same as the source-build variant.
#   end
#
# Sha256 sums come from the release.yml-generated `.sha256`
# sidecar files; copy verbatim into each `sha256` field.
