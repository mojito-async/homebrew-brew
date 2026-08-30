# mojito homebrew tap

    brew tap mojito/brew https://github.com/mojito-async/homebrew-brew.git
    brew install mojito/brew/mojolang            # stable
    brew install mojito/brew/mojolang-nightly     # nightly

Two formulae, both installing the Mojo toolchain entirely inside the Cellar
so a clean uninstall removes everything, caches included:

- **`mojolang`** — the stable/release channel, pinned by the mojito specs
  (currently 1.0.0b2). See `Formula/mojolang.rb` caveats.
- **`mojolang-nightly`** — Modular's `max-nightly` conda channel, roughly a
  daily build with no cross-build compatibility promise. See
  `Formula/mojolang-nightly.rb` caveats and its header comment for how to
  bump the pin.

They `conflicts_with` each other (both install the same `bin/mojo` path),
so pick one per machine — or use separate machines/containers for stable vs
nightly CI lanes, which is how `mojito-async`/`mojito-sys`'s own CI does it.
