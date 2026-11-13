#!/usr/bin/env python3
"""Builds a Swift package from the app's logic files (no SwiftUI) and runs the unit tests on Linux.
Usage: python3 tools/linux-check.py /path/to/swift/usr/bin"""
import os, re, shutil, subprocess, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, ".linux-check")
CORE = ["Models", "Catalog", "Pricing", "Planner", "HealthScore", "FoodProduct", "RecipeImporter", "HolidayMenu", "FirstFoods", "Lunchbox", "Backend", "PhotoCredits"]
SKIP_TESTS = ["testQuantityScaling", "testReceiptTotal", "testTimersInSteps", "testTierMapping"]  # live in SwiftUI or RevenueCat files
shutil.rmtree(OUT, ignore_errors=True)
src = os.path.join(OUT, "Sources", "SupperwiseCore"); tst = os.path.join(OUT, "Tests", "SupperwiseCoreTests")
os.makedirs(os.path.join(src, "Resources")); os.makedirs(tst)
for n in CORE: shutil.copy(os.path.join(ROOT, "Supperwise", "Model", n + ".swift"), src)
# The app's state and the debug demo mode are plain Swift too (Foundation and Observation): compile and test them here.
shutil.copy(os.path.join(ROOT, "Supperwise", "Model", "AppModel.swift"), src)
shutil.copy(os.path.join(ROOT, "Supperwise", "App", "Demo.swift"), src)
for f in os.listdir(os.path.join(ROOT, "Supperwise", "Resources")):
    if f.endswith(".json"): shutil.copy(os.path.join(ROOT, "Supperwise", "Resources", f), os.path.join(src, "Resources"))
def strip_funcs(code, names):
    for name in names:
        m = re.search(r"\n    func " + name + r"\(\)[^{]*\{", code)
        if not m: continue
        i, depth = m.end(), 1
        while depth: depth += {"{": 1, "}": -1}.get(code[i], 0); i += 1
        code = code[:m.start()] + code[i:]
    return code
for f in ["PlannerTests.swift", "FeatureTests.swift", "AppModelTests.swift", "BackendTests.swift"]:
    code = open(os.path.join(ROOT, "SupperwiseTests", f)).read()
    code = code.replace("@testable import Supperwise", "@testable import SupperwiseCore").replace("bundle: .main", "bundle: .module").replace("load(bundle: .main)", "load(bundle: .module)")
    code = "\n".join(l for l in code.split("\n") if "Feature." not in l and "Subscriptions." not in l)  # RevenueCat-side types
    open(os.path.join(tst, f), "w").write(strip_funcs(code, SKIP_TESTS))
open(os.path.join(OUT, "Package.swift"), "w").write('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SupperwiseCore",
  targets: [.target(name: "SupperwiseCore", resources: [.process("Resources")], swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
            .testTarget(name: "SupperwiseCoreTests", dependencies: ["SupperwiseCore"], swiftSettings: [.unsafeFlags(["-swift-version", "5"])])])
''')
swift = os.path.join(sys.argv[1], "swift") if len(sys.argv) > 1 else "swift"
sys.exit(subprocess.call([swift, "test"], cwd=OUT))
