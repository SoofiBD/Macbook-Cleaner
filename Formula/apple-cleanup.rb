class AppleCleanup < Formula
  desc "Safe macOS cleanup tool with terminal and local web interfaces"
  homepage "https://github.com/SoofiBD/Macbook-Cleaner"
  url "https://github.com/SoofiBD/Macbook-Cleaner/archive/refs/tags/v2.0.0.tar.gz"
  sha256 "6d3abe5ae4884b54f8e582d3130f4c49f56e0dffac6352f4e26086edd650bbcd"
  license "MIT"

  depends_on :macos
  depends_on "python@3.14"

  def install
    libexec.install "clean_mac.sh", "web"

    server = libexec/"web/server.py"
    old_script_path = 'SCRIPT_PATH = (WEB_DIR.parent / "clean_mac.sh").resolve()'
    unless server.read.include?("APPLE_CLEANUP_SCRIPT_PATH")
      inreplace server, old_script_path, <<~PYTHON.chomp
        def _get_script_path():
            """Use Homebrew's stable opt path when the launcher provides one."""
            configured = os.environ.get("APPLE_CLEANUP_SCRIPT_PATH")
            if configured:
                return Path(configured).expanduser()
            return (WEB_DIR.parent / "clean_mac.sh").resolve()


        SCRIPT_PATH = _get_script_path()
      PYTHON
    end

    python = formula_opt_bin("python@3.14")/"python3"
    (bin/"apple-cleanup").write_env_script(
      python,
      ["-u", libexec/"web/server.py"],
      { "APPLE_CLEANUP_SCRIPT_PATH" => opt_libexec/"clean_mac.sh" },
    )
    (bin/"apple-cleanup-cli").write_env_script(
      "/bin/bash",
      [libexec/"clean_mac.sh"],
      {},
    )
  end

  def caveats
    <<~EOS
      Start the local web dashboard with:
        apple-cleanup

      Start the terminal interface with:
        apple-cleanup-cli

      Some scans require Full Disk Access. Grant it to the terminal app you use
      under System Settings -> Privacy & Security -> Full Disk Access.

      Uninstalling the formula keeps runtime history and logs in:
        ~/.cache/apple-cleanup

      If you enable weekly cleanup, its LaunchAgent also remains in:
        ~/Library/LaunchAgents/com.cleanmac.weeklycleanup.plist
    EOS
  end

  test do
    output = shell_output("#{bin}/apple-cleanup-cli --help")
    assert_match "clean_mac v#{version}", output
    assert_match "--scan-json", output

    assert_path_exists libexec/"web/index.html"
    assert_path_exists libexec/"web/vendor/gsap.min.js"

    log = testpath/"server.log"
    pid = spawn(
      { "APPLE_CLEANUP_OPEN_BROWSER" => "0" },
      bin/"apple-cleanup",
      out: log.to_s,
      err: [:child, :out],
    )

    begin
      port = nil
      40.times do
        sleep 0.25
        match = log.read.match(%r{http://localhost:(\d+)}) if log.exist?
        if match
          port = match[1].to_i
          break
        end
      end
      refute_nil port, "dashboard did not start:\n#{log.read}"

      socket = TCPSocket.new("127.0.0.1", port)
      socket.write("GET / HTTP/1.0\r\nHost: 127.0.0.1:#{port}\r\n\r\n")
      response = socket.read
      socket.close
      assert_match "200 OK", response
      assert_match "<!DOCTYPE html>", response
    ensure
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
