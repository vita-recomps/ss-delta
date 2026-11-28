"""Runs a command up to --attempts times, each stopped after --minutes (#27): the release workflow's
download steps, where a source that trickles on must cost one attempt, not the job. The commands it
runs keep what they already checked, so a later attempt starts where the last one stopped. Works the
same on Windows, Linux and macOS (macOS has no timeout(1)).

usage: python -I tools/ci-retry.py [--attempts N] [--minutes M] -- <command> [<argument> ...]
"""
import argparse
import os
import signal
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument('--attempts', type=int, default=3)
    ap.add_argument('--minutes', type=float, default=5)
    ap.add_argument('command', nargs=argparse.REMAINDER)
    a = ap.parse_args()
    command = a.command[1:] if a.command[:1] == ['--'] else a.command
    if not command:
        ap.error('no command')
    for attempt in range(1, a.attempts + 1):
        with subprocess.Popen(command, start_new_session=os.name != 'nt') as process:
            try:
                code = process.wait(timeout=a.minutes * 60)
            except subprocess.TimeoutExpired:
                # CMake, git and Gradle can leave a worker behind holding a download or build open.
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/pid', str(process.pid), '/t', '/f'], check=False)
                    process.kill()
                else:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                print(f'::warning::attempt {attempt}/{a.attempts} took over {a.minutes:g} minutes: stopped', flush=True)
                continue
        if code == 0:
            return 0
        print(f'::warning::attempt {attempt}/{a.attempts} failed (exit {code})', flush=True)
    return 1


if __name__ == '__main__':
    sys.exit(main())
