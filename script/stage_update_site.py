"""Stage the public Sparkle feed and its two most recent versioned downloads for Pages."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

REPO = "jiuling9063/VoxInk"
SITE = "https://jiuling9063.github.io/VoxInk"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def recent_tags(releases):
    versions = []
    for release in releases:
        tag = release["tagName"]
        if release["isDraft"] or release["isPrerelease"] or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            continue
        version = tuple(map(int, tag[1:].split(".")))
        if version >= (0, 1, 27):
            versions.append((version, tag))
    return [tag for _, tag in sorted(versions, reverse=True)[:2]]


def verify_download(directory, tag):
    image = directory / f"VoxInk-{tag[1:]}-macOS-arm64.dmg"
    feed = directory / "appcast.xml"
    item, = ET.parse(feed).findall("channel/item")
    enclosure = item.find("enclosure")
    if (item.findtext(SPARKLE + "shortVersionString") != tag[1:]
            or enclosure is None or enclosure.get("url") != f"{SITE}/{tag}/{image.name}"
            or not enclosure.get(SPARKLE + "edSignature")
            or int(enclosure.get("length", "0")) != image.stat().st_size):
        raise ValueError(f"Feed does not match the versioned download for {tag}")
    with image.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if (directory / "SHA256SUMS.txt").read_text().split() != [digest, image.name]:
        raise ValueError(f"Incorrect DMG checksum for {tag}")


def public_tags(trigger):
    # The tag push can reach Actions just before the release and its assets become visible.
    for attempt in range(12):
        data = subprocess.check_output(["gh", "release", "list", "--repo", REPO, "--limit", "100",
                                        "--json", "tagName,isDraft,isPrerelease"])
        releases = json.loads(data)
        for release in releases:
            if release["tagName"] == trigger and not release["isDraft"]:
                if release["isPrerelease"]:
                    raise SystemExit("Prereleases are not deployed to the stable update channel.")
                return recent_tags(releases)
        if attempt < 11:
            time.sleep(5)
    raise RuntimeError(f"Public release {trigger} was not found")


def main(trigger, destination):
    tags = public_tags(trigger)
    for tag in tags:
        directory = destination / tag
        directory.mkdir(parents=True)
        image = f"VoxInk-{tag[1:]}-macOS-arm64.dmg"
        subprocess.run(["gh", "release", "download", tag, "--repo", REPO, "--dir", str(directory),
                        "--pattern", image, "--pattern", "appcast.xml", "--pattern", "SHA256SUMS.txt"],
                       check=True)
        verify_download(directory, tag)
    # Copy the exact signed bytes only after all assets have been verified.
    shutil.copyfile(destination / tags[0] / "appcast.xml", destination / "appcast.xml")


if __name__ == "__main__":
    main(sys.argv[1], Path(sys.argv[2]))
