# Task 1 — Launch-readiness config/metadata notes

## m2 — Package.resolved (action required on Mac/CI)

`.gitignore` no longer ignores `Package.resolved`, but no resolved file is
committed in this change. The correct file to commit is the **Xcode workspace**
resolved that XcodeGen/Xcode generates on a Mac:

    Readr.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

It pins ZIPFoundation for reproducible CI/release builds. It is not present in
the Linux sandbox (the project is regenerated from `project.yml` on macOS), so
it must be committed from a Mac or a CI run after `xcodegen generate` +
resolving packages.

Do NOT commit a Linux-generated root ReadrKit `Package.resolved`: the root
`Package.swift` declares zero dependencies, so it would either be empty or
contain unrelated swift-crypto/swift-asn1 Linux-patch artifacts that must never
be committed.

In the meantime, ZIPFoundation is deterministically pinned at project-generate
time via `exactVersion: "0.9.19"` in `project.yml`.
