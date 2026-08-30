class MojolangNightly < Formula
  desc "Mojo programming language toolchain (nightly channel)"
  homepage "https://www.modular.com/mojolang"

  # Same conda-package layout as the mojolang (stable) formula — see that
  # file's comments for why the .conda archive is unpacked by hand instead
  # of left to Homebrew's own downloader. The only real difference here is
  # the channel: max-nightly instead of max, and a version that changes
  # roughly daily rather than on a release cadence.
  #
  # To bump: fetch the channel's package index and pick the newest
  # mojo-compiler entry, the same way this pin was set:
  #
  #   curl -fsSL https://conda.modular.com/max-nightly/osx-arm64/repodata.json \
  #     | python3 -c 'import json,sys; d=json.load(sys.stdin); \
  #         p={**d.get("packages",{}), **d.get("packages.conda",{})}; \
  #         k=sorted(n for n in p if "mojo-compiler" in n)[-1]; \
  #         print(k); print(p[k]["sha256"])'
  #
  # First line printed is the new package filename — paste it in for the
  # `mojo-compiler-...-release.conda` segment of `url` below, keeping the
  # `.conda` extension. Second line is the new `sha256`.
  url "https://conda.modular.com/max-nightly/osx-arm64/mojo-compiler-25.6.0.dev2025090305-release.conda"
  sha256 "f594447623b286594605032d6f7663a90bc32ad56813aa2b5a131bb1542c630f"
  license :cannot_represent

  depends_on arch: :arm64
  depends_on "zstd"

  conflicts_with "mojolang", because: "both install bin/mojo from the same conda payload layout"

  def install
    conda = buildpath/"mojo-compiler-#{version}-release.conda"
    odie "expected .conda payload not found at #{conda}" unless conda.file?

    stage = buildpath/"stage"
    system "/usr/bin/unzip", "-q", conda, "-d", stage
    payload = Pathname.glob(stage/"pkg-mojo-compiler-*.tar.zst").first
    odie "no pkg-*.tar.zst member in .conda archive" unless payload

    libexec.mkpath
    system "sh", "-c",
           %Q(#{formula_opt_bin("zstd")}/zstd -dqc "#{payload}" | tar -xf - -C "#{libexec}")

    # rattler-build bakes the CI build-machine prefix into modular.cfg; conda
    # rewrites it on install, Homebrew must do the same or the driver cannot
    # locate std/compilerrt.
    cfg = libexec/"share/max/modular.cfg"
    baked = cfg.read[/^package_root\s*=\s*(\S+)/, 1]
    odie "could not detect baked prefix in modular.cfg" unless baked
    inreplace cfg, baked, libexec

    # The driver resolves std/compilerrt via $MODULAR_HOME/modular.cfg and
    # creates $MODULAR_HOME/cache at startup, so the default home lives in
    # the Cellar and uninstall removes toolchain and caches together.
    # Default MODULAR_HOME into the Cellar but honor an explicit override so
    # users can relocate caches (and brew's sandboxed tests can run at all).
    # A forced env here would clobber those overrides.
    (bin/"mojo").write <<~EOS
      #!/bin/bash
      export MODULAR_HOME="${MODULAR_HOME:-#{opt_libexec}/share/max}"
      exec "#{opt_libexec}/bin/mojo" "$@"
    EOS
    chmod 0755, bin/"mojo"
  end

  def caveats
    <<~EOS
      Mojo #{version} (nightly channel) is installed under:
        #{opt_libexec}

      This is a dev-channel build. Modular publishes a new one roughly daily
      and makes no compatibility promise between them — expect this pin to
      go stale faster than mojolang (stable) and to need more frequent bumps.

      The `mojo` driver wraps libexec/bin/mojo with MODULAR_HOME pinned inside
      this package, so no environment setup is needed and uninstall removes
      everything, caches included:

        brew uninstall mojolang-nightly && brew cleanup mojolang-nightly

      LSP server and lldb debugger live at:
        #{opt_libexec}/bin/mojo-lsp-server
        #{opt_libexec}/bin/mojo-lldb
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/mojo --version")

    # brew's test sandbox forbids writes into the Cellar, so hand the driver a
    # writable MODULAR_HOME for this run; real invocations use the Cellar home
    # baked into bin/mojo.
    (testpath/"mhome").mkpath
    cp libexec/"share/max/modular.cfg", testpath/"mhome/modular.cfg"
    (testpath/"hello.mojo").write <<~MOJO
      def main():
          print("hello", 6 * 7)
    MOJO
    # This Homebrew's shell helpers take no environment parameter, so wrap.
    (testpath/"run_hello").write <<~EOS
      #!/bin/bash
      export MODULAR_HOME="#{testpath}/mhome"
      exec "#{bin}/mojo" run "#{testpath}/hello.mojo"
    EOS
    chmod 0755, testpath/"run_hello"
    out = shell_output("#{testpath}/run_hello")
    assert_equal "hello 42", out.chomp.lines.last
  end
end
