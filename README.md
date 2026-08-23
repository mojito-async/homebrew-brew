# mojito homebrew tap

    brew tap mojito/brew https://github.com/spdrman/homebrew-brew.git
    brew install mojito/brew/mojolang

`mojolang` installs the Mojo toolchain pinned by the mojito specs
(currently 1.0.0b2) entirely inside the Cellar: clean uninstall removes
everything, caches included. See Formula/mojolang.rb caveats.
