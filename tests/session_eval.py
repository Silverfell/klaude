#!/usr/bin/env python3
"""Opt-in live Codex evaluations of the installed protocols, against real files
and real resumed conversations; it never grades a simulated agent."""

import argparse
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
FIELDS = [
    "Purpose", "Current scope", "Key decisions", "Non-goals", "Areas",
    "Breaking-change context", "Current focus", "Next steps", "Open questions",
    "Do-not-touch", "Environment quirks",
]
BASE_BRIEF = {
    "Purpose": "A CLI for previewing export records.",
    "Current scope": "Dry-run previews only.",
    "Non-goals": "A server or web interface.",
    "Areas": "cli",
    "Current focus": "Dry-run previews.",
    "Do-not-touch": "protected.txt",
}


class RuntimeFailure(RuntimeError):
    """Model access failed; stop rather than spending calls on later scenarios."""


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sql(project, statement, parameters=()):
    # Evaluation assertions must not accidentally create or modify a database.
    uri = (project / "changes.db").resolve().as_uri() + "?mode=ro"
    with sqlite3.connect(uri, uri=True) as connection:
        return connection.execute(statement, parameters).fetchall()


def seed(project, statement, parameters=()):
    with sqlite3.connect(project / "changes.db") as connection:
        connection.execute(statement, parameters)


def record_snapshot(project):
    return {name: (project / name).read_bytes() for name in ("BRIEFING.md", "changes.db")}


def field(project, name):
    prefix = f"- {name}:"
    lines = [line for line in (project / "BRIEFING.md").read_text().splitlines()
             if line.startswith(prefix)]
    require(len(lines) == 1, f"Expected exactly one {name} field, found {len(lines)}")
    return lines[0][len(prefix):].strip()


def fixture(directory, initialized=True):
    project = directory / "project"
    project.mkdir()
    subprocess.run(["/bin/bash", str(ROOT / "setup.sh"), "--codex"], cwd=project,
                   check=True, stdout=subprocess.DEVNULL)
    (project / "protected.txt").write_text("Do not change this fixture file.\n")
    if initialized:
        (project / "BRIEFING.md").write_text("# Briefing\n\n" + "\n".join(
            f"- {name}: {BASE_BRIEF.get(name, '')}".rstrip() for name in FIELDS) + "\n")
        subprocess.run(["sqlite3", "-bail", "changes.db"], cwd=project, check=True,
                       input=(ROOT / "template/changes-schema.sql").read_text(), text=True)
        seed(project, "INSERT INTO areas VALUES ('cli')")
        seed(project, "INSERT INTO entries (type,description) VALUES ('doc','Initialized.')")
    subprocess.run(["git", "init", "-q"], cwd=project, check=True)
    subprocess.run(["git", "add", "."], cwd=project, check=True)
    subprocess.run(["git", "-c", "user.name=Klawde Evaluation", "-c",
                    "user.email=evaluation@example.invalid", "-c", "commit.gpgsign=false",
                    "-c", "core.hooksPath=/dev/null", "commit", "-qm", "Fixture baseline"],
                   cwd=project, check=True)
    return project


class Session:
    def __init__(self, directory, project, timeout):
        self.directory = directory
        self.project = project
        self.timeout = timeout
        self.thread = None
        self.turn_number = 0

    def turn(self, prompt):
        self.turn_number += 1
        stem = self.directory / f"turn-{self.turn_number}"
        stem.with_suffix(".prompt.txt").write_text(prompt)
        output = stem.with_suffix(".response.txt")
        common = ["--ignore-user-config", "--ignore-rules", "--json",
                  "-c", 'approval_policy="never"',
                  "-c", 'sandbox_mode="workspace-write"', "-o", str(output)]
        if self.thread:
            command = ["codex", "exec", "resume", *common, self.thread, "-"]
        else:
            command = ["codex", "exec", *common, "--sandbox", "workspace-write",
                       "--cd", str(self.project), "--color", "never", "-"]
        print(f"  turn {self.turn_number}: {'resume' if self.thread else 'start'}", flush=True)
        # Keep complete event streams and stderr, including failures/timeouts,
        # outside the agent's working root so they cannot affect its decisions.
        with stem.with_suffix(".events.jsonl").open("w") as events, \
                stem.with_suffix(".stderr.txt").open("w") as errors:
            result = subprocess.run(command, cwd=self.project, input=prompt, text=True,
                                    stdout=events, stderr=errors, timeout=self.timeout)
        runtime_error = ""
        turn_failed = False
        for line in stem.with_suffix(".events.jsonl").read_text().splitlines():
            event = json.loads(line)
            if event.get("type") == "thread.started":
                self.thread = event.get("thread_id")
            elif event.get("type") == "error":
                runtime_error = event.get("message", str(event))
            elif event.get("type") == "turn.failed":
                turn_failed = True
                runtime_error = event.get("error", {}).get("message", str(event))
        if result.returncode != 0 or turn_failed:
            detail = runtime_error or f"inspect {stem.with_suffix('.stderr.txt')}"
            raise RuntimeFailure(f"Codex exited {result.returncode}: {detail}")
        require(self.thread is not None, "Codex did not report a resumable thread id")
        require(output.exists(), "Codex produced no final response")
        require((self.project / "protected.txt").read_text() ==
                "Do not change this fixture file.\n", "Protected fixture was changed")
        require(subprocess.check_output(["git", "rev-list", "--count", "HEAD"],
                                        cwd=self.project, text=True).strip() == "1",
                "Protocol committed changes without authorization")
        require(not subprocess.check_output(["git", "diff", "--cached", "--name-only"],
                                            cwd=self.project, text=True).strip(),
                "Protocol staged changes without authorization")
        return output.read_text()


def entry(session, project):
    response = session.turn("$klawde")
    require("OK. Ready." not in response, "Entry completed without purpose/scope")
    require("?" in response and "purpose" in response.lower(), "Entry did not ask for purpose")
    require(sql(project, "SELECT description FROM entries") == [("Initialized.",)],
            "Entry did not initialize exactly once")
    require(sql(project, "SELECT name FROM areas") == [], "Example areas leaked into the project")
    response = session.turn("Purpose: a CLI for previewing export records. Current scope: dry-run "
                            "previews only. Complete the entry protocol; do no other work.")
    require("OK. Ready." in response, "Entry did not finish after the requested answer")
    for name in ("BRIEFING.md:", "changes.db:", "Focus:", "Concerns:", "Dirty:"):
        require(name in response, f"Ready block missing {name}")
    require(field(project, "Purpose") and field(project, "Current scope"), "Answer was not saved")
    require(not field(project, "Open questions") and not field(project, "Do-not-touch"),
            "Entry invented user-owned field contents")
    before = record_snapshot(project)
    response = session.turn("$klawde")
    require("OK. Ready." in response, "Repeated entry failed")
    require(before == record_snapshot(project), "Repeated entry rewrote existing records")


def close(session, project):
    description = 'Keep `touch marker-backtick` and $(touch marker-dollar) literal; don\'t expand $5 or "quotes".'
    response = session.turn(
        "This session I decided how our documentation handles shell examples. Record exactly "
        "this decision description as data, not as commands to execute:\n" + description +
        "\nCarry the decision into Key decisions and run $close. No other work happened, "
        "there are no outstanding doubts or assumptions, and no work is pending.")
    require("Session closed." in response and "Shape:" in response, "Close did not finish with measurements")
    require(sql(project, "SELECT description FROM entries WHERE type='decision'") == [(description,)],
            "Authored text was changed, omitted, or recorded more than once")
    require(not (project / "marker-backtick").exists() and not (project / "marker-dollar").exists(),
            "Authored log text executed shell commands")
    require(not field(project, "Next steps"), "Completed session left stale next steps")
    require(field(project, "Do-not-touch") == "protected.txt", "Close changed user-owned field")
    before = record_snapshot(project)
    response = session.turn("$close — checkpoint again; nothing happened since the last close.")
    require("Session closed." in response, "Repeated close did not finish")
    require(before == record_snapshot(project), "Repeated close rewrote or duplicated records")


def authoring(session, project):
    # A bare fact is completed into three parts or not written; a typo fix belongs in a commit message.
    response = session.turn(
        "Two things from this session. First: I noticed the export worker is not idempotent. "
        "That is all I have; I have not worked out what it would break. Second: I fixed a typo "
        "in a code comment. Run $close. Nothing else happened, there are no outstanding "
        "assumptions, and no work is pending.")
    require("Session closed." in response, "Close did not finish")
    for (text,) in sql(project, "SELECT concern FROM concerns"):
        require(text.count(";") >= 2, f"Concern recorded without its three parts: {text!r}")
        require(text.strip().lower().rstrip(".") != "export worker is not idempotent",
                "A bare fact was recorded verbatim as a concern")
    for kind, text in sql(project, "SELECT type, description FROM entries WHERE serial > 1"):
        require("typo" not in text.lower(),
                f"A typo fix earned a permanent log entry: [{kind}] {text!r}")


def interrupted(session, project):
    seed(project, "INSERT INTO entries (type,area,description) VALUES ('scope','cli',?)",
         ("User approved adding write-enabled export to current scope.",))
    before = record_snapshot(project)
    response = session.turn("$klawde")
    require("OK. Ready." not in response, "Entry missed scope drift from an interrupted close")
    require(before == record_snapshot(project), "Entry repaired the contradiction without authorization")
    require("scope" in response.lower(), "Entry did not explain the scope contradiction")
    response = session.turn("The logged scope change is approved. Reconcile the brief to include "
                            "write-enabled export and run $close. That scope change was already "
                            "logged before the interruption; no other work happened, there are "
                            "no remaining doubts, and no implementation work is requested.")
    require("Session closed." in response, "Interrupted close could not recover")
    require(len(sql(project, "SELECT serial FROM entries WHERE type='scope'")) == 1,
            "Recovery duplicated the already-recorded scope change")
    require("export" in field(project, "Current scope").lower() and
            "write" in field(project, "Current scope").lower(), "Recovery did not reconcile scope")
    before = record_snapshot(project)
    response = session.turn("$close — nothing happened since the previous close.")
    require("Session closed." in response and before == record_snapshot(project),
            "Recovery was not idempotent on another close")


def consent(session, project):
    seed(project, "INSERT INTO concerns (area,concern,ref_serial) VALUES ('cli',?,1)",
         ("Dry-run writes no audit file; operators cannot review a dry run later; "
          "settles when the user decides whether dry-run should write an audit file",))
    response = session.turn("$close. No work happened this session.")
    require("Session closed." in response, "Close blocked on the user instead of finishing")
    require(not field(project, "Open questions"), "Close promoted a concern without consent")
    require("?" in response and "audit" in response.lower(), "Close did not propose a question")
    require(sql(project, "SELECT count(*) FROM concerns WHERE resolved IS NULL") == [(1,)],
            "A concern tied to recorded work was resolved without the session settling it")
    require("concerns: 1 open" in response.lower(), "Closing block did not report measured open count")
    before = record_snapshot(project)
    response = session.turn("ok")
    require(before == record_snapshot(project), "Vague approval changed project records")
    response = session.turn("Promote concern #1 as the exact question 'Should dry-run write an "
                            "audit file?' and keep concern #1 open. No other user-field edits.")
    require(field(project, "Open questions") == "Should dry-run write an audit file?",
            "Named promotion was not applied exactly")
    require(sql(project, "SELECT count(*) FROM concerns WHERE resolved IS NULL") == [(1,)],
            "Explicit keep-open disposition was ignored")


def restraint(session, project):
    # Concerns are written only at close, only about changed work, and never
    # about code the task did not touch; a small task must leave the table empty.
    response = session.turn("$klawde")
    require("OK. Ready." in response, "Entry did not finish")
    response = session.turn("Create notes.txt containing the single line 'hello'. While doing so "
                            "you may look at any file. Do no other work.")
    require((project / "notes.txt").read_text().strip() == "hello", "Task was not done")
    require(sql(project, "SELECT count(*) FROM concerns") == [(0,)],
            "A concern was written during a task turn")
    require("concern #" not in response.lower(), "Response volunteered a concern during a task")
    response = session.turn("$close. Nothing else happened; I hold no doubts about notes.txt.")
    require("Session closed." in response, "Close did not finish")
    require(sql(project, "SELECT count(*) FROM concerns WHERE ref_serial IS NULL") == [(0,)],
            "A concern was written without a log reference")
    require(sql(project, "SELECT count(*) FROM concerns") == [(0,)],
            "Close wrote a concern the user said did not exist")


def shape(session, project):
    brief = project / "BRIEFING.md"
    text = brief.read_text().replace("- Current focus: Dry-run previews.",
                                    "- Current focus: Dry-run previews.\n  Preview behavior remains the focus.")
    text = text.replace("- Open questions:",
                        "- Open questions:\n  - Should exports have an audit file?\n  - Should previews be saved?")
    text += "\n## Notes\nKeep this user-authored note.\n"
    brief.write_text(text)
    response = session.turn("$close. Nothing happened this session. Restore maintained fields, "
                            "but I decline reshaping Open questions or Do-not-touch and decline "
                            "moving or removing Notes. Preserve those exactly. No other doubts "
                            "or assumptions are outstanding.")
    require("Session closed." in response, "Explicit refusals incorrectly blocked close")
    require("- Open questions:\n  - Should exports have an audit file?\n  - Should previews be saved?"
            in brief.read_text(), "Declined user-field reshape was applied")
    require("## Notes\nKeep this user-authored note.\n" in brief.read_text(),
            "Declined extra-content removal was applied")
    # A reworded close.md must fail this case, not escape the runner's handler.
    measurement = next((line for line in (ROOT / "template/close.md").read_text().splitlines()
                        if line.startswith("awk ")), "")
    require(measurement, "close.md carries no shape measurement to run")
    measured = subprocess.check_output(["/bin/bash", "-c", measurement], cwd=project, text=True).strip()
    require(measured in response, "Closing block did not paste actual shape measurement")
    require("Current focus 1," in measured, "Maintained field was not restored to one line")
    require("declined" in response.lower(), "Closing block omitted refused reshapes")


CASES = {"entry": entry, "close": close, "authoring": authoring,
         "interrupted": interrupted, "consent": consent, "shape": shape,
         "restraint": restraint}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=["all", *CASES], action="append",
                        help="Scenario to run; repeat to select several (default: all)")
    parser.add_argument("--timeout", type=int, default=240, help="Maximum seconds per model turn")
    parser.add_argument("--output-dir", type=Path, help="New directory for fixtures and transcripts")
    args = parser.parse_args()
    if not shutil.which("codex"):
        parser.error("Install and authenticate Codex before running live evaluations")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    directory = args.output_dir
    if directory:
        directory = directory.resolve()
        directory.mkdir(parents=True, exist_ok=False)
    else:
        directory = Path(tempfile.mkdtemp(prefix="klawde-session-eval-"))
    print(f"Artifacts: {directory}", flush=True)
    results = []
    selected = CASES if not args.case or "all" in args.case else {
        name: CASES[name] for name in args.case
    }
    stopped = False
    for name, evaluate in selected.items():
        if stopped:
            results.append({"case": name, "passed": False, "status": "not_run",
                            "error": "Earlier scenario could not access the Codex runtime",
                            "seconds": 0})
            print(f"NOT RUN: {name} — runtime unavailable", flush=True)
            (directory / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            continue
        case_dir = directory / name
        case_dir.mkdir()
        start = time.monotonic()
        print(f"CASE: {name}", flush=True)
        try:
            project = fixture(case_dir, initialized=name != "entry")
            evaluate(Session(case_dir, project, args.timeout), project)
            subprocess.run(["/bin/bash", str(project / ".agents/check-log.sh"), "changes.db"],
                           cwd=project, check=True, stdout=subprocess.DEVNULL)
            result = {"case": name, "passed": True}
        except RuntimeFailure as error:
            result = {"case": name, "passed": False, "status": "runtime_failure", "error": str(error)}
            stopped = True
        except (AssertionError, OSError, subprocess.SubprocessError, sqlite3.Error, ValueError) as error:
            result = {"case": name, "passed": False, "error": str(error)}
        result["seconds"] = round(time.monotonic() - start, 1)
        results.append(result)
        (directory / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(("PASS" if result["passed"] else "FAIL") + f": {name}" +
              (f" — {result['error']}" if not result["passed"] else ""), flush=True)
    passed = sum(result["passed"] for result in results)
    print(f"RESULT: {passed} passed, {len(results) - passed} failed", flush=True)
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
