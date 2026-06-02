// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "t",
	platforms: [.macOS(.v15)],
	products: [.executable(name: "t", targets: ["t"])],
	targets: [
		.executableTarget(name: "t"),
		.testTarget(
			name: "tTests",
			dependencies: ["t"]
		)
	]
)
