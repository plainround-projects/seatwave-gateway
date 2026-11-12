// One place decides where dependencies come from; a project that adds its own repository fails the build.
dependencyResolutionManagement {
    repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS
    repositories {
        mavenCentral()
    }
}

// The plugins' own dependencies are locked too, in settings-gradle.lockfile.
buildscript {
    configurations.classpath {
        resolutionStrategy.activateDependencyLocking()
    }
}

rootProject.name = "seatwave-gateway"

// Six programs, one repository: the edge gateway, the two SeatWave services behind it, the mobile
// backend-for-frontend, the lab's token issuer stand-in, and the JDK-only lab tools.
include("gateway", "catalog", "booking", "mobile-bff", "issuer", "labtools")
