// swift-tools-version:6.3
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("StrictConcurrency"),
    .enableExperimentalFeature("SuppressedAssociatedTypes"),
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
]


let package = Package(
    name: "feather-database-sqlite",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "SQLiteNIOExtras", targets: ["SQLiteNIOExtras"]),
        .library(name: "FeatherDatabaseSQLite", targets: ["FeatherDatabaseSQLite"]),
    ],
    traits: [
        "ServiceLifecycle",
        .default(
            enabledTraits: [
                "ServiceLifecycle",
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.16.1"),
        .package(url: "https://github.com/vapor/sqlite-nio", from: "1.13.2"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle", from: "2.8.0"),
        .package(
            url: "https://github.com/feather-framework/feather-database",
            exact: "1.0.0-rc.3"
        ),
    ],
    targets: [
        .target(
            name: "SQLiteNIOExtras",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SQLiteNIO", package: "sqlite-nio"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "FeatherDatabaseSQLite",
            dependencies: [
                .target(name: "SQLiteNIOExtras"),
                .product(name: "FeatherDatabase", package: "feather-database"),
                .product(
                    name: "ServiceLifecycle",
                    package: "swift-service-lifecycle",
                    condition: .when(traits: ["ServiceLifecycle"])
                ),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SQLiteNIOExtrasTests",
            dependencies: [
                .target(name: "SQLiteNIOExtras"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "FeatherDatabaseSQLiteTests",
            dependencies: [
                .target(name: "FeatherDatabaseSQLite"),
                .product(
                    name: "ServiceLifecycleTestKit",
                    package: "swift-service-lifecycle",
                    condition: .when(
                        traits: ["ServiceLifecycle"]
                    )
                ),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
