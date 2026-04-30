# homebrew-tap

Homebrew tap for [`wild`](https://github.com/Wildstuff/the-wild) — multi-tribe LLM agent runtime.

## Install

```sh
brew install wildstuff/tap/wild
```

After install:

```sh
wild up
wild doctor
wild --version
```

First boot pulls plugin Wasm component images from `ghcr.io/wildstuff/plugins/*`,
caches under `~/.wild/profiles/<active>/oci-cache/`.

## License

Apache-2.0
