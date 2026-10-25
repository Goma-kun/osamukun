// swift-tools-version: 5.9
import PackageDescription

// おさむくんの Mac / iPhone アプリ用。拡張機能の sidepanel.js のうち、画面を持たない部分
// （定型文の形・CSV/TSV の読み書き・検索・元に戻す・保存）をそのまま移した層。
// 拡張と同じ答えを返すことを Tests/ と ../test/parity_test.mjs で確かめる。
let package = Package(
    name: "OsamukunCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OsamukunCore", targets: ["OsamukunCore"]),
    ],
    targets: [
        .target(name: "OsamukunCore"),
        // JS 版と答えを突き合わせるための入口。JSON を受けて JSON を返すだけ
        .executableTarget(name: "ok-probe", dependencies: ["OsamukunCore"]),
        .testTarget(name: "OsamukunCoreTests", dependencies: ["OsamukunCore"]),
    ]
)
