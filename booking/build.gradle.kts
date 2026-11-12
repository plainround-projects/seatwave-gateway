// The booking service: holds and bookings, each owned by the fan the gateway names.
plugins {
    alias(libs.plugins.spring.boot)
}

dependencies {
    implementation(libs.spring.boot.starter.webmvc)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.result4j)
    testImplementation(libs.spring.boot.starter.test)
}
