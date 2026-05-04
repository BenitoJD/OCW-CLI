# Troubleshooting

## Homebrew appears stuck on macOS

If `brew install BenitoJD/ocw/ocw` prints OCW metadata and then appears to hang, check whether Homebrew is waiting on macOS Xcode discovery:

```bash
ps -ax -o pid=,ppid=,stat=,command= | grep mdfind
```

Homebrew can call Spotlight `mdfind` to locate Xcode. If that lookup never returns, the install can look like an OCW formula problem even though the release tarball and checksum are valid.

Use the release installer while repairing local Homebrew:

```bash
curl -fsSL https://raw.githubusercontent.com/BenitoJD/OCW-CLI/main/scripts/install-release.sh | bash
ocw homebrew doctor
```

Useful local checks:

```bash
xcode-select -p
/usr/bin/mdfind 'kMDItemCFBundleIdentifier == com.apple.dt.Xcode || kMDItemCFBundleIdentifier == com.apple.Xcode'
```

Common fixes are resetting or reinstalling Xcode Command Line Tools and rebuilding the Spotlight index for the system volume. Apple documents the Command Line Tools install path as `/Library/Developer/CommandLineTools`: https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/

Homebrew common issue docs: https://docs.brew.sh/Common-Issues
