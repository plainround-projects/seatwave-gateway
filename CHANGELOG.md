# Changelog

All notable changes to this project are written here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-12

The first version, built from the code seed of Module 11 (`_tools/module-11-code/` in the course's
tools folder) and run in full: `./gradlew check`, the Compose stack, the stack tests, the labs and
two of the module's failure reproductions.

### Added

- Six programs: the edge gateway (Spring Cloud Gateway 5.0.4, Server Web MVC, on Spring Boot
  4.1.2), the catalog service, the booking stand-in, the mobile backend-for-frontend, the token
  issuer stand-in and the JDK-only lab tools.
- The Gradle wrapper 9.9.1 (checksums of the jar and the distribution checked), lockfiles for every
  program and for the build's own classpath.
- Tests for booking (`HoldBookTest`, `BookingHttpTest`, `BookingPropertiesTest`), for the issuer
  (`KeyRingTest`, `KeyRingCliTest`, `IssuerHttpTest`, `IssuerPropertiesTest`), for the BFF's HTTP
  endpoint (`SeatScreenHttpTest`), for the lab token checker (`TokenCheckerTest`), and for the
  gateway's refusal when the key set cannot be fetched (`KeySetUnavailableTest`); the seed had none.
- `StackTest`, tagged `stack`, run by `scripts/stack.sh test` against the running stack.
- `scripts/stack.sh` (up, down, test, status; dry run by default) and `scripts/lab.sh` (Lab 1's
  routes and latency, Lab 3's slow booking, failure modes 1 and 4).
- `LatencyProbe` takes `subject=fan-42` as its fourth argument to time booking directly with the
  header the gateway sends.
- One Gradle task per lab program: `tokenWalk`, `tokenCost`, `fanOut`, `latencyProbe`.

### Fixed (against the seed)

- On the public port, a path without a handler (for example `/actuator/health`) answered `401`:
  Boot's error forward passed the security chain again and fell under deny-by-default. Error
  forwards are now permitted, and the path answers `404`.
- `KeyRing` accepted an elliptic-curve key on any curve although its message said P-256; it now
  refuses every curve but P-256 at start-up.
- `KeyRingCli rotate` on a missing key file ended in a stack trace; it now says to run `generate`.
- The `409` detail said "is held by another fan" also when the same fan held the seat under another
  key; it now says "is already held".
- `TokenChecker` (lab tools) threw on a time claim that was not a number; it now refuses it as a
  missing claim.
- `SeatScreenServiceTest` used the service's real 100 ms booking budget, so a busy machine could
  turn a healthy call into a timeout; its timeouts are now wider than the budgets.
- The build's own classpath carried commons-lang3 3.16.0 (CVE-2025-48924, build time only); it is
  constrained to 3.22.0.
- The base image digest of `eclipse-temurin:25.0.5_8-jre-noble` was renewed: the tag was rebuilt on
  12 November 2026.
