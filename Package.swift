// swift-tools-version: 5.9
// Package.swift
import PackageDescription

let package = Package(
    name: "TrainTracker",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TrainTracker",
            path: "Sources/TrainTracker"
        ),
        .testTarget(
            name: "TrainTrackerTests",
            dependencies: ["TrainTracker"],
            path: "Tests/TrainTrackerTests"
        )
    ]
)
