#!/usr/bin/env python3
"""Check incremental hardware claims against the Swift-owned offline profile catalog."""
import argparse
import json
from pathlib import Path
import sys

STATUSES = {"maintainer_validated", "contributor_validated", "mapped", "not_tested", "unsupported"}
VALIDATED = {"maintainer_validated", "contributor_validated"}


def check_claim(feature, claim, profile, root):
    errors = []
    status = claim.get("status")
    if status not in STATUSES:
        return [f"{feature}: unknown status {status!r}"]
    if feature not in profile["capabilities"]:
        return [f"{feature}: unknown code capability"]
    supported = profile["capabilities"][feature]
    if status in VALIDATED | {"mapped"} and not supported:
        errors.append(f"{feature}: claimed capability is not shipped by this profile")
    if status == "unsupported" and supported:
        errors.append(f"{feature}: unsupported claim contradicts shipped capability")
    if status == "maintainer_validated" and not profile["isLocallyValidated"]:
        errors.append(f"{feature}: contributor-only profile cannot be called maintainer validated")
    if status in VALIDATED:
        if not isinstance(claim.get("source"), str) or not claim["source"].strip():
            errors.append(f"{feature}: validation requires a source/credit")
        evidence = claim.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            errors.append(f"{feature}: validation requires evidence paths")
        else:
            for item in evidence:
                if not isinstance(item, str) or not item:
                    errors.append(f"{feature}: invalid evidence path")
                    continue
                path = (root / item).resolve()
                if Path(item).is_absolute() or root not in path.parents or not path.is_file():
                    errors.append(f"{feature}: missing or external evidence {item}")
    return errors


def validate(manifest, catalog, root):
    root = root.resolve()
    if manifest.get("schema_version") != 1 or catalog.get("schemaVersion") != 1:
        return ["Unsupported validation manifest/catalog schema"]
    profiles = {(row["id"], row["transport"]): row for row in catalog["profiles"]}
    devices = manifest.get("devices")
    if not isinstance(devices, list) or not devices:
        return ["Manifest requires a nonempty devices list"]
    errors, seen = [], set()
    for device in devices:
        key = (device.get("profile_id"), device.get("transport"))
        if key in seen:
            errors.append(f"Duplicate device {key}")
        seen.add(key)
        profile = profiles.get(key)
        if profile is None:
            errors.append(f"Unregistered profile/transport {key}")
            continue
        try:
            products = [int(value, 0) if isinstance(value, str) else value for value in device["product_ids"]]
            if not products or any(type(value) is not int or value not in profile["productIDs"] for value in products):
                errors.append(f"{key}: unregistered product IDs")
        except (KeyError, TypeError, ValueError):
            errors.append(f"{key}: invalid product_ids")
        features = device.get("features")
        if not isinstance(features, dict) or not features:
            errors.append(f"{key}: require at least one explicit feature status")
            continue
        for feature, claim in features.items():
            if not isinstance(claim, dict):
                errors.append(f"{key}/{feature}: invalid claim")
                continue
            errors.extend(f"{key}/{error}" for error in check_claim(feature, claim, profile, root))
        limits = device.get("limitations", [])
        if not isinstance(limits, list) or any(not isinstance(item, str) or not item.strip() for item in limits):
            errors.append(f"{key}: limitations must be nonempty strings")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    try:
        errors = validate(json.loads(args.manifest.read_text()), json.loads(args.catalog.read_text()), args.root)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print(f"Invalid validation input: {error}", file=sys.stderr)
        return 1
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("[open-snek] Device validation claims match registered identities, capabilities, and evidence paths.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
