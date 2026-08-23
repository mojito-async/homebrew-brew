class Mojolang < Formula
  desc "Mojo programming language toolchain"
  homepage "https://www.modular.com/mojolang"
  license :cannot_represent

  # Upstream ships the toolchain as a conda package (.conda = zip containing a
  # pkg-*.tar.zst payload). The .conda extension is opaque to Homebrew, so the
  # archive lands in buildpath untouched. We unpack it into libexec so every
  # file lives in the Cellar and `brew uninstall` removes all of it.
  url "https://conda.modular.com/max/osx-arm64/mojo-compiler-1.0.0b2-release.conda"
  sha256 "91c4d590a152ec2e26846955fcd7ec02796dfaffefa006a1c0c5790575be2051"

  depends_on arch: :arm64
  depends_on :macos
  depends_on "zstd"

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
      Mojo #{version} is installed under:
        #{opt_libexec}

      The `mojo` driver wraps libexec/bin/mojo with MODULAR_HOME pinned inside
      this package, so no environment setup is needed and uninstall removes
      everything, caches included:

        brew uninstall mojolang && brew cleanup mojolang

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
