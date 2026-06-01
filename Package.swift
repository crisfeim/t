// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "t",
	platforms: [.macOS(.v15)],
	products: [
		.executable(name: "t", targets: ["t"])
	],
	dependencies: [.package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")],
	targets: [
		.executableTarget(
			name: "t",
			dependencies: [
				.product(name: "ArgumentParser", package: "swift-argument-parser")
			]
		),
		.testTarget(
			name: "tTests",
			dependencies: ["t"]
		)
	]
)
