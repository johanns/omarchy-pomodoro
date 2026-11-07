#!/usr/bin/env python3
"""Drives the jg.pomodoro test hooks over IPC and checks the lock behavior.

Run with: python3 tests/lock-trials.py
It changes the live timer and the session count. It saves
~/.local/state/omarchy/pomodoro.json first and prints how to put it back.
"""
import json, os, shutil, subprocess, sys, time

STATE = os.path.expanduser("~/.local/state/omarchy/pomodoro.json")
BACKUP = STATE + ".before-lock-trials"
if os.path.exists(STATE):
    shutil.copyfile(STATE, BACKUP)

def ipc(*args):
    out = subprocess.run(["omarchy-shell", "jg.pomodoro", *args], capture_output=True, text=True)
    if "not found" in out.stdout + out.stderr:
        sys.exit(f"IPC method missing: {args}")
    return out.stdout

def status():
    time.sleep(0.4)  # a lock read answers on the next event loop turn
    return json.loads(ipc("status"))

failures = 0
def check(name, **expected):
    global failures
    s = status()
    bad = {k: (s[k], v) for k, v in expected.items() if s[k] != v}
    shown = {k: s[k] for k in ["phase", "running", "remaining", "completedFocus", "lockHeld"]}
    print(("PASS " if not bad else "FAIL ") + name, shown, "" if not bad else f"mismatch {bad}")
    failures += bool(bad)
    return s

def focus_running():
    ipc("simulateLock", "unlocked")
    s = status()
    if s["phase"] == "break": ipc("skip")       # starts focus
    else: ipc("reset"); ipc("start")
    s = status()
    assert s["phase"] == "focus" and s["running"], s

def break_running():
    focus_running(); ipc("finishPhase")      # focus ends -> break starts
    s = status()
    assert s["phase"] == "break" and s["running"], s

# AC3: running focus pauses at a locked check, keeping its time
focus_running(); time.sleep(1.2)
ipc("simulateLock", "locked"); ipc("checkLock")
s = check("AC3 locked check pauses running focus", phase="focus", running=False, lockHeld=True)
assert s["remainingMs"] < s["durationMs"]
# AC6: unlocked check continues it from the remaining time
ipc("simulateLock", "unlocked"); ipc("checkLock")
s2 = check("AC6 unlocked check continues lock-paused focus", phase="focus", running=True, lockHeld=False)
print("     remaining kept:", s["remaining"], "->", s2["remaining"])

# AC6: a session the owner paused is never continued by a check
ipc("pause"); ipc("checkLock")
check("AC6 owner-paused focus stays paused on unlocked check", phase="focus", running=False, lockHeld=False)

# AC4: a break that ends while locked holds focus at full length
break_running(); count = status()["completedFocus"]
ipc("simulateLock", "locked"); ipc("finishPhase")
check("AC4 break ends while locked: focus held", phase="focus", running=False, lockHeld=True, remainingMs=status()["durationMs"], completedFocus=count)
ipc("checkLock")
check("AC4 locked check keeps the hold", phase="focus", running=False, lockHeld=True)
# AC6: unlocked check starts the held session at full length
ipc("simulateLock", "unlocked"); ipc("checkLock")
check("AC6 unlocked check starts held focus", phase="focus", running=True, lockHeld=False)

# AC3 (with AC13): a break ending while unlocked starts focus at once
break_running(); ipc("simulateLock", "unlocked"); ipc("finishPhase")
check("AC3/AC13 break ends while unlocked: focus starts", phase="focus", running=True, lockHeld=False)

# AC4: breaks keep running while locked
break_running(); ipc("simulateLock", "locked"); ipc("checkLock")
check("AC4 locked check leaves a running break alone", phase="break", running=True, lockHeld=False)

# AC7: Start on a lock-paused session hands it back
focus_running(); ipc("simulateLock", "locked"); ipc("checkLock"); ipc("start")
check("AC7 Start on lock-paused focus", phase="focus", running=True, lockHeld=False)
# AC7: Pause on a lock-paused session hands it back; unlock does not continue it
ipc("checkLock"); ipc("pause"); ipc("simulateLock", "unlocked"); ipc("checkLock")
check("AC7 Pause on lock-paused focus, then unlocked check", phase="focus", running=False, lockHeld=False)
# AC7: Reset on a held session
break_running(); ipc("simulateLock", "locked"); ipc("finishPhase"); ipc("reset"); ipc("simulateLock", "unlocked"); ipc("checkLock")
check("AC7 Reset on held focus, then unlocked check", phase="focus", running=False, lockHeld=False)

# AC11: Skip on a running break starts focus; count unchanged
break_running(); count = status()["completedFocus"]; ipc("skip")
check("AC11 Skip on running break starts focus", phase="focus", running=True, completedFocus=count)
# AC11: Stop on a paused break starts focus
break_running(); ipc("pause"); ipc("stop")
check("AC11 Stop on paused break starts focus", phase="focus", running=True)
# AC11: Skip on focus leaves the break idle
focus_running(); ipc("skip")
check("AC11 Skip on focus leaves break idle", phase="break", running=False)

ipc("simulateLock", "off")
print(f"\n{failures} failed")
if os.path.exists(BACKUP):
    print(f"Timer state was saved to {BACKUP}. To restore it:")
    print(f"  cp {BACKUP} {STATE} && omarchy restart shell")
sys.exit(1 if failures else 0)
