#!/usr/bin/env python3
"""Check that the mutation ledger still describes the suite that exists.

`db/mutation-expectations.txt` records which negative scenarios have actually been watched
failing. It is only worth anything while it is complete: add a negative test and forget the
ledger, and the mutation job keeps passing on the entries it still knows about. Nothing goes
red, and the coverage number quietly becomes a lie.

So every scenario tagged `@negative` must be accounted for, as one of:

    expect: <name>          the weakened schema is expected to catch it
    not-coverable: <name>   recorded as out of reach, with the reason alongside

and the ledger must not name scenarios that no longer exist.

That cross-check is the entire reason the `@negative` tag exists. Before it, four of the five
tag families in this repository selected nothing at all — decoration that looked like
configuration.

Run it directly; it needs nothing but the working tree:

    python3 scripts/check_mutation_ledger.py
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
LEDGER = REPO / "src/test/resources/db/mutation-expectations.txt"
FEATURES = REPO / "src/test/resources/features"

# Not a negative scenario, but a legitimate ledger entry: the consumer contract fails against the
# real service once the unique index is gone. Exempt from the "must be tagged @negative" side of
# the check, because tagging a contract scenario @negative would be a lie.
CONTRACT_ENTRY = "the real service satisfies the consumer contract"

# The tag sits on its own line above the scenario, possibly with other tags between.
NEGATIVE_SCENARIO = re.compile(
    r"^[ \t]*@negative[ \t]*\n"
    r"(?:[ \t]*@[\w]+[ \t]*\n)*"
    r"[ \t]*Scenario(?: Outline)?:[ \t]*(.+?)[ \t]*$",
    re.MULTILINE,
)


def read_ledger() -> set[str]:
    accounted: set[str] = set()
    for line in LEDGER.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        for key in ("expect:", "not-coverable:"):
            if line.startswith(key):
                accounted.add(line[len(key) :].strip())
    return accounted


def read_tagged() -> dict[str, str]:
    tagged: dict[str, str] = {}
    for feature in sorted(FEATURES.glob("*.feature")):
        text = feature.read_text(encoding="utf-8")
        for match in NEGATIVE_SCENARIO.finditer(text):
            tagged[match.group(1)] = feature.name
    return tagged


def main() -> int:
    accounted = read_ledger()
    tagged = read_tagged()

    missing = {name: f for name, f in tagged.items() if name not in accounted}
    stale = accounted - set(tagged) - {CONTRACT_ENTRY}

    print(f"{len(tagged)} @negative scenario(s), {len(accounted)} ledger entr(ies)")

    for name, feature in sorted(missing.items()):
        print(f"::error::@negative scenario missing from the ledger: {name} ({feature})")
    for name in sorted(stale):
        print(
            "::error::ledger names a scenario that no longer exists, or that lost its "
            f"@negative tag: {name}"
        )

    if missing or stale:
        print("::error::mutation-expectations.txt no longer describes the suite.")
        return 1

    print("Ledger and suite agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
