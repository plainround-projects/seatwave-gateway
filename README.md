# seatwave-gateway

SeatWave, the ticket-booking service of the course System Design Fundamentals, split into a catalog service and a booking service, with an API gateway in front that checks every token once and passes the fan's identity inward, and a mobile backend-for-frontend that draws the seat screen in one call. This is the project of **Module 11, "The API gateway"**.

## What it shows

- An edge gateway on Spring Cloud Gateway 5.0.4 (Server Web MVC) and Spring Boot 4.1.2, with virtual threads: three routes by path, method and version (`catalog-v1`, `booking-v1`, `mobile-bff-v1`), deny by default for everything else.
- One token check per request in front of booking and the BFF: ES256 only, a key id, the issuer's key set (cached, refetched on an unknown key id), required claims, expiry and not-before with 30 s of skew, exact issuer and audience. Every refusal is problem details with one reason, counted by reason; an unreachable key set is `503` with `Retry-After`, never a token let through.
- The identity filter: the client's `Authorization` and every `X-SeatWave-*` header it sent are removed in any spelling, and `X-SeatWave-Subject` carries the verified fan.
- A mobile backend-for-frontend that fans the seat screen out to four parallel parts with a timeout each, and answers a partial screen, marked as partial, when an optional part is late.
- A token issuer stand-in that publishes its key set and signs 15-minute tokens (no password: the real login is Module 38), and JDK-only lab tools.

Measured on the runs below (this Mac, Docker Desktop's virtual machine, every timing through its port forwarder): the gateway added 0.23 ms at p50 and 2.01 ms at p99 on the public route at 500 requests per second, and used 550 µs of CPU per proxied request after a 60 s warm-up; one ES256 token check costs 381.9 µs on one thread; with booking slowed to 2 s, the seat screen still answered in about 121 ms, marked partial.

## Prerequisites

- JDK 25 (the build's toolchain asks for 25; it was run on Eclipse Temurin 25.0.2; the images run 25.0.5).
- Docker with Compose v2 for the stack (run on Docker Desktop, engine 24.0.6, Compose v2.23.0-desktop.1). `./gradlew check` needs no Docker.
- `curl` on the machine for the scripts.

## Dependencies

Every version is pinned in `gradle/libs.versions.toml`; transitive versions are in each program's `gradle.lockfile`, the build's own in `buildscript-gradle.lockfile`. All were checked on Maven Central and the Spring project pages on 12 November 2026, and OSV listed no vulnerability for any of the 166 locked jars that day.

| Coordinates | Version | Checked | License | Why the JDK alone is not enough |
|---|---|---|---|---|
| `org.springframework.boot:spring-boot-dependencies` (BOM) and the Spring Boot Gradle plugin | 4.1.2 | 12 Nov 2026 | Apache-2.0 | An HTTP server, JSON binding, validated settings and graceful shutdown, in one tested set of versions. |
| `org.springframework.cloud:spring-cloud-dependencies` (BOM) | 2025.1.4 | 12 Nov 2026 | Apache-2.0 | The release train of Spring Cloud Gateway 5.0.4 that supports Boot 4.1.x. |
| `org.springframework.cloud:spring-cloud-starter-gateway-server-webmvc` | 5.0.4 | 12 Nov 2026 | Apache-2.0 | Routes, predicates and filters as configuration, and a correct proxy. |
| `org.springframework.boot:spring-boot-starter-security-oauth2-resource-server` (Spring Security 7.1.2) | managed by Boot | 12 Nov 2026 | Apache-2.0 | The filter chain before every route and the key-set-backed JWT decoder. |
| `com.nimbusds:nimbus-jose-jwt` | 10.9.1 | 12 Nov 2026 | Apache-2.0 | ES256 signing in the issuer, the release Spring Security itself uses (10.10 is newer). |
| `org.springframework.boot:spring-boot-starter-webmvc`, `-restclient`, `-validation`, `-actuator` | managed by Boot | 12 Nov 2026 | Apache-2.0 | Endpoints, long-lived REST clients, start-up checks of every setting, metrics. |
| `com.github.sviperll:result4j` | 1.2.0 | 12 Nov 2026 | Apache-2.0 | Booking's expected refusals as a `Result` with a sealed error type. |
| `org.springframework.boot:spring-boot-starter-test` (JUnit Jupiter 6.0.3, AssertJ, Awaitility) | managed by Boot | 12 Nov 2026 | EPL-2.0, Apache-2.0 | The tests. |
| `org.apache.commons:commons-lang3` (build classpath only, a constraint) | 3.22.0 | 12 Nov 2026 | Apache-2.0 | Replaces 3.16.0 on the Spring Boot plugin's classpath (CVE-2025-48924). |
| Spotless, google-java-format, JaCoCo (build) | 8.11.0, 2.0.0, 0.8.16 | 12 Nov 2026 | Apache-2.0, Apache-2.0, EPL-2.0 | One enforced format and a 0.80 line-coverage floor per program. |

The image: `eclipse-temurin:25.0.5_8-jre-noble@sha256:e3b6f7887a50f20d8f07abf279d8a81a5953fb398a9555bd9edd56b9bd15968c`, a Docker Official Image with an `arm64` variant, checked on Docker Hub on 12 November 2026. Gradle 9.9.1 through the wrapper; its jar and distribution checksums match services.gradle.org.

## Commands and what they printed

Run on 12 November 2026 on an Apple M2 Max (12 cores, 32 GB, macOS 27.2) with other programs running; containers in Docker Desktop's Linux virtual machine (12 CPUs, 8 GB); the probe on the Mac. The timed runs were taken while no other course project was measuring; the 1-minute load average was 5.95 before the JDK-only programs, 5.01 before Lab 1 and 3.54 before failure mode 1. Your numbers will differ.

Build, test and check the format and the coverage floor (no Docker needed):

```text

BUILD SUCCESSFUL in 19s
53 actionable tasks: 53 executed
```

117 tests in six programs; line coverage per program, each above the 0.80 floor:

```text
gateway     tests  31 failures 0 lines 187/190 = 0.984
catalog     tests  13 failures 0 lines 74/78 = 0.949
booking     tests  29 failures 0 lines 86/89 = 0.966
mobile-bff  tests   8 failures 0 lines 108/112 = 0.964
issuer      tests  21 failures 0 lines 79/85 = 0.929
labtools    tests  15 failures 0 lines 87/89 = 0.978
total tests 117
```

The whole check also passes from a copy at a long path and from a folder with a space in its name:

```text
$ ./gradlew clean check   (in a copy at a path of 312 characters)
BUILD SUCCESSFUL in 20s
exit status 0
$ ./gradlew clean check   (in a copy at a path of 201 characters, with a space in a folder name)
BUILD SUCCESSFUL in 19s
exit status 0
```

Start the stack, run the stack tests and stop it again (a dry run unless `--run` is given):

```text
$ scripts/stack.sh test --run --yes
StackTest > refusesAWriteToTheCatalogAndAnUnknownVersionWithoutAToken() PASSED
StackTest > servesTheCatalogWithoutAToken() PASSED
StackTest > refusesAHoldWithoutATokenBeforeItReachesBooking() PASSED
StackTest > drawsTheSeatScreenWithTheFansOwnHoldThroughTheMobileRoute() PASSED
StackTest > refusesAnUnroutedPathEvenWithAGoodToken() PASSED
StackTest > answersHealthOnTheManagementPortOnly() PASSED
StackTest > holdsASeatForTheFanTheTokenNamesNotTheOneAForgedHeaderNames() PASSED
StackTest > refusesSomethingThatIsNotATokenAsMalformed() PASSED
stack is up after 3 s: gateway, issuer and catalog answer
stack is down: no container, network or volume of seatwave-gateway is left
```

A token, the seat screen with it, and two refusals:

```text
$ curl -s -X POST 'http://127.0.0.1:21102/v1/tokens?subject=fan-42' | cut -c1-60
{"expiresIn":900,"tokenType":"Bearer","accessToken":"eyJraWQ

$ curl -s -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:21100/mobile/v1/events/1/seat-screen?section=A' | cut -c1-120
{"eventName":"Arena on-sale night","section":"A","seats":["A-1","A-2","A-3","A-4","A-5","A-6","A-7","A-8","A-9","A-10","
$ curl -s -H "Authorization: Bearer $TOKEN" 'http://127.0.0.1:21100/mobile/v1/events/1/seat-screen?section=A' | grep -o '"partial".*'
"partial":true,"missing":["holds","bookings"]}
$ curl -s -i 'http://127.0.0.1:21100/mobile/v1/events/1/seat-screen?section=A' | grep -E '^HTTP|^WWW-Authenticate|reason'
HTTP/1.1 401 
WWW-Authenticate: Bearer
{"type":"https://seatwave.example/problems/token-refused","title":"The request's token was refused","status":401,"reason":"missing","instance":"urn:uuid:..."}
$ curl -s -o /dev/null -w '%{http_code}\n' -H 'Authorization: Bearer not-a-token' 'http://127.0.0.1:21100/v1/holds?eventId=1'
401
```

The JDK-only lab tools (Section 8 of the module runs them with `javac` and `java`; `./gradlew -q :labtools:tokenWalk`, `:tokenCost`, `:fanOut` and `:latencyProbe` run the same classes):

```text
$ javac -Xlint:all -Werror -d build/labtools labtools/src/main/java/io/plainround/seatwave/gateway/labtools/*.java
$ java -cp build/labtools io.plainround.seatwave.gateway.labtools.TokenWalk
good                          accepted after steps 1 to 6: X-SeatWave-Subject: fan-42
1 wrong signature             refused at step 5 (signature): the signature does not verify with key issuer-key-1
2 wrong issuer                refused at step 6 (wrong-issuer): iss is http://evil.example, not http://issuer:8080
3 wrong audience              refused at step 6 (wrong-audience): aud is partner-api, not seatwave-api
4 expired                     refused at step 6 (expired): exp 2026-11-11T08:59:00Z + 30 s skew is not after now 2026-11-11T09:00:00Z
5 not yet valid               refused at step 6 (not-yet-valid): nbf 2026-11-11T09:02:00Z - 30 s skew is after now 2026-11-11T09:00:00Z
6 alg none                    refused at step 3 (unsigned): alg is none: anybody could have written it
7 HS256 keyed with public key refused at step 3 (algorithm): alg is HS256, only ES256 is allowed
8 missing                     refused at step 0 (missing): no Authorization: Bearer header
a verifier that let the header pick HS256 and used the public key as its secret would accept token 7: true
$ java -cp build/labtools io.plainround.seatwave.gateway.labtools.TokenCheckCost
20000 checks timed after 20000 warm-up checks, 40000 of 40000 accepted
one ES256 token check: 381.9 microseconds on one thread, about 2619 checks per core-second
$ java -cp build/labtools io.plainround.seatwave.gateway.labtools.FanOutDemo
scenario        way                               screens  p50 ms  p99 ms  max ms  partial  body bytes to phone
booking 5 ms    app: five sequential calls             50    42.2    49.0    49.0        0                46051
booking 5 ms    BFF: one call, fanned out              50    16.7    19.1    19.1        0                 8018
booking 2 s     app: five sequential calls              5  4044.4  4047.4  4047.4        0                46051
booking 2 s     BFF: one call, fanned out               5   103.5   109.3   109.3        5                 8030
model, not measured: on 4G at 80 ms per round trip, the app's screen is about 42.2 + 5 x 80 = 442.2 ms; the BFF's is about 16.7 + 10 + 1 x 80 = 106.7 ms
```

Lab 1, what the gateway adds (`scripts/lab.sh latency --run`; catalog and booking get a port for this lab only):

```text
plan: lab latency on the Compose project seatwave-gateway: catalog and booking published on 127.0.0.1:21110 and 21111 for this lab; four probe runs at 500/s for 30 s; then compose.yaml's ports again
== catalog, direct: http://127.0.0.1:21110/v1/events/1/seats?section=A&limit=100 at 500/s for 30 s, after a 10 s warm-up
planned 15000, recorded 15000, answered 15000, no answer 0
statuses (0 = no answer): {200=15000}
latency of answered requests: p50 0.81 ms, p99 2.45 ms, max 54.16 ms
gateway CPU during the run: 35 ms, 2 us per planned request
== catalog, through the gateway (public route): http://127.0.0.1:21100/v1/events/1/seats?section=A&limit=100 at 500/s for 30 s, after a 10 s warm-up
planned 15000, recorded 15000, answered 15000, no answer 0
statuses (0 = no answer): {200=15000}
latency of answered requests: p50 1.04 ms, p99 4.46 ms, max 68.17 ms
gateway CPU during the run: 11592 ms, 772 us per planned request
== booking, direct (X-SeatWave-Subject as the gateway sends it): http://127.0.0.1:21111/v1/holds?eventId=1 at 500/s for 30 s, after a 10 s warm-up
planned 15000, recorded 15000, answered 15000, no answer 0
statuses (0 = no answer): {200=15000}
latency of answered requests: p50 0.77 ms, p99 2.44 ms, max 55.33 ms
gateway CPU during the run: 31 ms, 2 us per planned request
== booking, through the gateway (token checked): http://127.0.0.1:21100/v1/holds?eventId=1 at 500/s for 30 s, after a 10 s warm-up
planned 15000, recorded 15000, answered 15000, no answer 0
statuses (0 = no answer): {200=15000}
latency of answered requests: p50 1.35 ms, p99 3.95 ms, max 71.66 ms
gateway CPU during the run: 15493 ms, 1032 us per planned request
report: build/runs/latency.txt
```

The same with a 60 s warm-up (`WARMUP=60 scripts/lab.sh latency --run`), the timing and CPU lines:

```text
latency of answered requests: p50 0.87 ms, p99 3.56 ms, max 58.95 ms
latency of answered requests: p50 1.04 ms, p99 3.01 ms, max 63.35 ms
latency of answered requests: p50 0.85 ms, p99 2.35 ms, max 58.27 ms
latency of answered requests: p50 1.31 ms, p99 2.48 ms, max 87.56 ms
gateway CPU during the run: 33 ms, 2 us per planned request
gateway CPU during the run: 8250 ms, 550 us per planned request
gateway CPU during the run: 20 ms, 1 us per planned request
gateway CPU during the run: 12924 ms, 861 us per planned request
```

Lab 3, booking slowed to 2 s (`scripts/lab.sh slow-booking --run`), the first and last lines:

```text
plan: lab slow-booking on the Compose project seatwave-gateway: booking restarted with SEATWAVE_BOOKING_READ_DELAY=2s; twenty screens; booking restarted without it
screen 1: status 503, 0.281412 s, no screen in the body
screen 2: status 200, 0.118108 s, "partial":true,"missing":["holds","bookings"]
screen 3: status 200, 0.111920 s, "partial":true,"missing":["holds","bookings"]
screen 20: status 200, 0.122063 s, "partial":true,"missing":["holds","bookings"]
report: build/runs/slow-booking.txt
```

Failure mode 1, the gateway at 0.5 CPU and then stopped (`scripts/lab.sh bottleneck --run`):

```text
plan: lab bottleneck on the Compose project seatwave-gateway: docker update --cpus 0.5 on the gateway; probe runs at 100 250 500 requests/s; --cpus 2 again; then the gateway stopped 5 s into a 20 s run and started again
== the gateway at 0.5 CPU, public route, 100/s for 15 s after a 5 s warm-up
planned 1500, recorded 1500, answered 1500, no answer 0
statuses (0 = no answer): {200=1500}
latency of answered requests: p50 3.25 ms, p99 69.02 ms, max 88.03 ms
== the gateway at 0.5 CPU, public route, 250/s for 15 s after a 5 s warm-up
planned 3750, recorded 3750, answered 3750, no answer 0
statuses (0 = no answer): {200=3750}
latency of answered requests: p50 1.68 ms, p99 58.56 ms, max 78.00 ms
== the gateway at 0.5 CPU, public route, 500/s for 15 s after a 5 s warm-up
planned 7500, recorded 7500, answered 7500, no answer 0
statuses (0 = no answer): {200=7500}
latency of answered requests: p50 1.15 ms, p99 72.68 ms, max 86.87 ms
== the only gateway stopped 5 s into a 20 s run at 500/s
planned 10000, recorded 10000, answered 2483, no answer 7517
statuses (0 = no answer): {0=7517, 200=2483}
latency of answered requests: p50 1.06 ms, p99 7.10 ms, max 52.13 ms
report: build/runs/bottleneck.txt
```

Failure mode 4, a key rotation (`scripts/lab.sh rotate --run`):

```text
plan: lab rotate on the Compose project seatwave-gateway: ./gradlew :issuer:keys rotate; the issuer restarted; two tokens through the gateway
rotate: 2 key(s), signing key d268bb41-56d8-464b-949d-efd7949b2e16
key ids in the published key set: "kid":"d268bb41-56d8-464b-949d-efd7949b2e16" "kid":"c2702036-6f50-42ce-b9fd-8538a6b58709" 
token signed with the new key -> 200
token signed before the rotation -> 200
report: build/runs/rotate.txt
```

Nothing of the project is left after `scripts/stack.sh down --run`:

```text
$ docker ps -a --filter label=com.docker.compose.project=seatwave-gateway -q | wc -l; docker network ls --filter label=com.docker.compose.project=seatwave-gateway -q | wc -l; docker volume ls --filter label=com.docker.compose.project=seatwave-gateway -q | wc -l
0
0
0
```

## Where a new gateway filter goes

The request path has fixed places, by servlet filter order. Spring Security's chain (the token check) runs at `SecurityFilterProperties.DEFAULT_FILTER_ORDER`; `IdentityHeaderFilter` runs at `DEFAULT_FILTER_ORDER + 1` (registered in `SecurityConfiguration.identityHeaderFilter`). A filter that needs the verified fan, such as Module 12's rate limiter, goes in its own `@Configuration` class with a `FilterRegistrationBean` at `DEFAULT_FILTER_ORDER + 2` or later, so it runs for every request and no new route can skip it. A filter that must run before the token check (a coarse per-address limit) takes an order below `DEFAULT_FILTER_ORDER`. A change to one route only goes in that route's `filters:` list in `gateway/src/main/resources/application.yaml`. Before adding any filter, run it through the module's checklist (Section 6e) and measure it with `scripts/lab.sh latency`.

## Ports

All on 127.0.0.1 only: the gateway on 21100, its management port (health, metrics) on 21101, the issuer on 21102. `scripts/lab.sh latency` publishes catalog on 21110 and booking on 21111 for that lab only. Catalog, booking and the BFF publish no port otherwise.

## Project structure

See `ARCHITECTURE.md` for packages, the dependency rule, a data-flow diagram, walk-throughs, decisions and invariants.

```text
compose.yaml, Dockerfile, .dockerignore
scripts/         stack.sh, lab.sh, common.sh
gateway/         io.plainround.seatwave.gateway.edge: routes, token check, identity header
catalog/         io.plainround.seatwave.gateway.catalog: events and seats
booking/         io.plainround.seatwave.gateway.booking: holds (stand-in, in memory)
mobile-bff/      io.plainround.seatwave.gateway.bff: the seat screen
issuer/          io.plainround.seatwave.gateway.issuer: key set and token stand-in
labtools/        io.plainround.seatwave.gateway.labtools: the JDK-only programs
```

## What is simplified

- Booking keeps holds in memory, one lock and maps that only grow; SeatWave keeps them in Module 10's PostgreSQL tables.
- The issuer signs a token for any fan name and checks no password; Module 38 replaces it with a real identity provider and adds a limit on key-set refetches for unknown key ids.
- One instance of each program; production runs several behind Module 10's balancer pair.
- Plain HTTP on one private Docker network; the identity header is trustworthy only because nothing else can reach the services.
- No rate limit; Module 12 adds one to this gateway in its own project.
- Failure modes 2 and 5 of the module (a filter that calls the catalog, filters added one by one) are not reproduced: they need filters that this repository deliberately does not ship.

## No CI on purpose

This repository has no `.github/` folder and no CI workflow, on purpose: the course's owner verifies every project locally, with the commands above.

## The Compose path

`compose.yaml` holds all the infrastructure under the project name `seatwave-gateway`; `scripts/stack.sh` starts it, tests it and brings it down with `down -v`, then checks that no container, network or volume of the project is left. The issuer's private key is generated into `build/keys/` (ignored by git and Docker) and mounted as a Compose secret.

## License

MIT, see `LICENSE`.
