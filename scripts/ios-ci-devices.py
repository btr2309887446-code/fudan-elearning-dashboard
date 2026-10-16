"""Select iOS 26 simulators, including the reported iPhone 15 Plus model."""

import json
import subprocess
import sys


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True)


runtimes = json.loads(simctl("list", "runtimes", "-j"))["runtimes"]
candidates = [
    runtime for runtime in runtimes
    if runtime.get("isAvailable")
    and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
    and runtime["version"].split(".")[0] == "26"
]
if not candidates:
    raise SystemExit("An available iOS 26 runtime is required for the calendar regression.")
runtime = max(candidates, key=lambda item: tuple(map(int, item["version"].split("."))))
devices = json.loads(simctl("list", "devices", "available", "-j"))["devices"].get(runtime["identifier"], [])
phone = next((device for device in devices if device["name"] == "iPhone 15 Plus"), None)
if phone is None:
    types = json.loads(simctl("list", "devicetypes", "-j"))["devicetypes"]
    model = next(item for item in types if item["name"] == "iPhone 15 Plus")
    phone = {"udid": simctl("create", "iPhone 15 Plus", model["identifier"], runtime["identifier"]).strip(), "name": "iPhone 15 Plus"}
tablet = next(device for device in devices if device["name"].startswith("iPad") and device.get("isAvailable"))
for device in (phone, tablet):
    print(f"Testing {device['name']} on iOS {runtime['version']}", file=sys.stderr)
    print(device["udid"])
