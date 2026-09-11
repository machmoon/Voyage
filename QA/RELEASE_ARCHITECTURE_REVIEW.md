# Release architecture review — September 11, 2026

## Source of truth

App Store Connect confirms Voyage: Lock In 1.0 (3) is live. Version 1.1 (4) has been uploaded, processed VALID, and is In Review. The full app lived on `release/app-review-on-submission-base`, while
GitHub main contained a smaller lineage. `codex/unified-app-store-release` joins
main, the release branch, both audio branches, and the lifecycle and recorder
worktrees. All original branch pointers are retained. Archive/stash backups are
historical snapshots, not additional features to restore.

## Open-source references inspected

- [isowords FileClient](https://github.com/pointfreeco/isowords/blob/main/Sources/FileClient/Client.swift)
  and [LocalDatabaseClient](https://github.com/pointfreeco/isowords/blob/main/Sources/LocalDatabaseClient/Interface.swift):
  persistence is an explicit throwing dependency. Tests can supply a failure
  instead of accidentally exercising the real filesystem.
- [isowords test dependencies](https://github.com/pointfreeco/isowords/blob/main/Sources/FileClient/TestKey.swift):
  test defaults and preview behavior are distinct. Production behavior should not
  quietly become a no-op when a dependency fails.
- [DuckDuckGo Live Activity manager](https://github.com/duckduckgo/apple-browsers/blob/main/iOS/DuckDuckGo/VPNSnoozeLiveActivityManager.swift):
  use a system-owned stale date and enumerate surviving activities when cleaning
  up. This matches the lifecycle fix adapted into Voyage during the merge.
- [Apple icon metadata](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html):
  compiled iOS icon metadata is nested under CFBundleIcons/CFBundlePrimaryIcon.
  Voyage's release checker previously rejected this valid structure.

No external source files or new architectural frameworks were copied into the
release. These references support small, testable service boundaries; they do
not justify replacing a working local-first app with another product's backend.

## Concrete changes in this integration

- Preserve uncommitted origin provenance, boarding layout, Live Activity deferral,
  and end-to-end tests.
- Retain the complete renderer, recorded PA, receipt-render caching, and current
  signing/privacy configuration when reconciling main.
- Integrate recorder history and cabin-service work without replacing the newer
  replay schema. New stored fields have migration-compatible defaults.
- Expire stale Live Activities and sweep orphaned activities on foregrounding.
- Preserve every flight phase for tiny and compressed legs. Keep the injected
  session clock for recorded arrival timestamps and recorder departure times.
- Consolidate duplicate settings controls. Keep the newer audio implementation
  instead of adding an unused alternative engine-tone subsystem.
- Repair the shipping branch/team/export configuration and add regression tests
  for archive icon validation. Stop tracking Wrangler's local cache and logs.

## Remaining reliability work to investigate separately

`FlightSession.finishSession` still uses `try? modelContext.save()`. A failed save
can therefore display an arrival without durable history. Follow the explicit
throwing persistence-boundary pattern above: expose a retryable save failure to
the UI, and test a deliberately failing save. Do not treat logging alone as a fix.

The app's startup container can fall back to in-memory storage. That fallback
should be visible to the user so they do not assume new flights are durable.
The existing legacy-store migration test passes, but a forced disk-write failure
needs its own test.

Audio and optional network fallbacks need explicit diagnostics and failure
injection. Retain useful offline behavior, but distinguish unavailable data from
successful live data. A wholesale backend migration is not required for this.

## Verification

257 iOS unit tests, 14 worker tests, and 3 release-validator tests passed.
The UI suite passed 9 of 12 initially; after correcting test setup, foreground
waiting, and destination selection, all three targeted rechecks passed. The
signed 1.1 (4) archive passed validation. App Store Connect confirms the version
in review references build a4307b92-aae2-410c-a88a-be396df02630.

The new marketing copy in AppStore/listing.md is a proposal, not the metadata
currently in review. The five-hour retry condition was not met: the updated
build is already submitted.

## Earlier submission notices

Apple displayed an updated Developer Program agreement requiring Account Holder
acceptance. The owner must review any outstanding agreement; this audit does not attest to acceptance. The prior local submission
notes also leave commercial-use rights for the bundled ElevenLabs announcements
unconfirmed; confirm those rights independently. The version subsequently reached In Review; this audit did not make a new content-rights attestation.
