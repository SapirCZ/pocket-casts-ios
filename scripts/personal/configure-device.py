#!/usr/bin/env python3
"""Generate a phone-only project for personal signing beside the upstream project."""
import argparse
import json
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--team", required=True, help="Your Apple development team ID")
parser.add_argument("--bundle-id", default="com.sapircz.pocketcasts.books")
args = parser.parse_args()
if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
    parser.error("--team must be a 10-character Apple team ID")
if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
    parser.error("--bundle-id must be a reverse-DNS identifier")

root = Path(__file__).resolve().parents[2]
source = root / "podcasts.xcodeproj"
target = root / ".personal-device.xcodeproj"
target.mkdir(exist_ok=True)
project = json.loads(subprocess.check_output([
    "plutil", "-convert", "json", "-o", "-", str(source / "project.pbxproj")
]))
objects = project["objects"]
app_id = next(key for key, obj in objects.items()
              if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "podcasts")
app = objects[app_id]
# Keep resource/credential generation, but omit extensions and Watch provisioning.
app["dependencies"] = [key for key in app["dependencies"]
                       if objects[objects[key]["target"]]["name"] == "PreBuildActions"]
app["buildPhases"] = [key for key in app["buildPhases"]
                      if objects[key].get("name") not in {
                          "Embed App Extensions", "Embed Watch Content", "Embed App Clips"
                      }]
attributes = objects[project["rootObject"]]["attributes"]["TargetAttributes"][app_id]
attributes.update(DevelopmentTeam=args.team, ProvisioningStyle="Automatic", SystemCapabilities={})

local = root / "artifacts"
local.mkdir(exist_ok=True)
info = plistlib.loads((root / "podcasts/podcasts-Info.plist").read_bytes())
info.update(CFBundleDisplayName="Sapir Books", CFBundleName="Sapir Books")
info["UIBackgroundModes"] = [mode for mode in info.get("UIBackgroundModes", [])
                             if mode != "remote-notification"]
# Avoid claiming the installed Pocket Casts app's deep-link scheme.
for url_type in info.get("CFBundleURLTypes", []):
    if url_type.get("CFBundleURLName") == "au.com.shiftyjelly.podcasts":
        url_type["CFBundleURLSchemes"] = ["sapirbooks"]
(local / "device-Info.plist").write_bytes(plistlib.dumps(info))
# Basic on-device testing needs no upstream App Groups, Push, Siri or CarPlay grants.
(local / "device.entitlements").write_bytes(plistlib.dumps({}))
for config_id in objects[app["buildConfigurationList"]]["buildConfigurations"]:
    settings = objects[config_id]["buildSettings"]
    settings.update({
        "DEVELOPMENT_TEAM": args.team,
        "PRODUCT_BUNDLE_IDENTIFIER_ROOT": args.bundle_id,
        "PRODUCT_BUNDLE_IDENTIFIER": args.bundle_id,
        "CODE_SIGN_STYLE": "Automatic",
        "CODE_SIGN_IDENTITY": "Apple Development",
        "CODE_SIGN_ENTITLEMENTS": "artifacts/device.entitlements",
        "PROVISIONING_PROFILE_SPECIFIER": "",
        "PROVISIONING_PROFILE": "",
        "INFOPLIST_FILE": "artifacts/device-Info.plist",
    })
    for key in list(settings):
        if key.startswith("PROVISIONING_PROFILE_SPECIFIER["):
            del settings[key]

(target / "project.pbxproj").write_bytes(plistlib.dumps(project, sort_keys=False))
scheme_dir = target / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme = (source / "xcshareddata/xcschemes/Pocket Casts Staging.xcscheme").read_text()
scheme = scheme.replace("container:podcasts.xcodeproj", "container:.personal-device.xcodeproj")
# Build only the app; the upstream unit-test target isn't a personal-device product.
tree = ET.fromstring(scheme)
entries = tree.find("BuildAction/BuildActionEntries")
for entry in list(entries):
    if entry.find("BuildableReference").get("BlueprintIdentifier") != app_id:
        entries.remove(entry)
(scheme_dir / "Sapir Books.xcscheme").write_bytes(ET.tostring(tree, encoding="utf-8", xml_declaration=True))
resolved = source / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if resolved.exists():
    destination = target / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(resolved, destination)
print("Personal phone project ready: .personal-device.xcodeproj (Sapir Books)")
