// The edge gateway: routes by path, method and version, validates every token once, and passes the
// fan's identity inward.
plugins {
    alias(libs.plugins.spring.boot)
}

dependencies {
    implementation(libs.spring.cloud.starter.gateway.server.webmvc)
    implementation(libs.spring.boot.starter.security.oauth2.resource.server)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.spring.boot.starter.actuator)
    testImplementation(libs.spring.boot.starter.test)
}

// The tests tagged "stack" talk to the running Compose stack on its published 127.0.0.1 ports.
// scripts/stack.sh test starts the stack, runs this task and stops the stack on every path.
tasks.register<Test>("stackTest") {
    group = "verification"
    description = "Runs the tests against the running stack; scripts/stack.sh test starts and stops it."
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform {
        includeTags("stack")
    }
    // The stack is outside Gradle's view, so these tests are never up to date.
    outputs.upToDateWhen { false }
    testLogging {
        events("passed", "failed", "skipped")
    }
}
