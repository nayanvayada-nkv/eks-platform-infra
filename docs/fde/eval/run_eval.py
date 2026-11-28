"""Answer-quality eval for a tenant (FDE step 6). Standard library only.

Usage: URL=https://<cloudfront> KEY=tk_... python3 docs/fde/eval/run_eval.py
Each question has the facts a correct answer must contain (expect_all / expect_any), the source
document it must cite, or expect_not_found for questions the documents do not answer.
Prints per-question results and the score; exits 1 below the go-live bar (90%).
"""

import json
import os
import pathlib
import sys
import urllib.error
import urllib.request

PASS_BAR = 0.9


def ask(url: str, key: str, question: str):
    req = urllib.request.Request(
        f"{url}/ask",
        data=json.dumps({"question": question}).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as err:
        return err.code, json.loads(err.read() or b"{}")


def grade(case: dict, status: int, body: dict) -> tuple[bool, str]:
    answer = (body.get("answer") or "").lower()
    if case.get("expect_not_found"):
        ok = status == 404 or any(p in answer for p in ("cannot find", "can't find", "not in", "no information"))
        return ok, "said not found" if ok else "answered something not in the documents"
    if status != 200:
        return False, f"HTTP {status}"
    facts_ok = all(f.lower() in answer for f in case.get("expect_all", [])) and (
        not case.get("expect_any") or any(f.lower() in answer for f in case["expect_any"])
    )
    cited = case["source"] in body.get("sources", [])
    return facts_ok and cited, ("ok" if facts_ok else "missing fact") + ("" if cited else ", source not cited")


def main() -> int:
    url, key = os.environ["URL"].rstrip("/"), os.environ["KEY"]
    cases = json.loads((pathlib.Path(__file__).parent / "questions.json").read_text())
    passed = 0
    for i, case in enumerate(cases, 1):
        status, body = ask(url, key, case["q"])
        ok, why = grade(case, status, body)
        passed += ok
        print(f"{'PASS' if ok else 'FAIL'} {i:2d}. {case['q'][:70]:70s} {why}")
    score = passed / len(cases)
    print(f"\nScore: {passed}/{len(cases)} = {score:.0%} (go-live bar {PASS_BAR:.0%})")
    return 0 if score >= PASS_BAR else 1


if __name__ == "__main__":
    sys.exit(main())
