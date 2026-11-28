"""Waits, in a release workflow job, until another job of the same run has finished (#27): the PC jobs
build their executables while the android job runs, and wait for its APK only before laying out the
setup. Exits 0 when that job succeeded, 1 when it failed, was cancelled or was skipped, or after
--minutes without an end. Reads GITHUB_API_URL, GITHUB_REPOSITORY and GITHUB_RUN_ID (set by Actions)
and GH_TOKEN (the job's token, which needs actions: read).

usage: python -I tools/ci-wait-job.py <job name> [--minutes N]
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request


def jobs():
    url = (f'{os.environ.get("GITHUB_API_URL", "https://api.github.com")}/repos/{os.environ["GITHUB_REPOSITORY"]}'
           f'/actions/runs/{os.environ["GITHUB_RUN_ID"]}/jobs?per_page=100')
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {os.environ["GH_TOKEN"]}',
                                               'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)['jobs']


def main():
    ap = argparse.ArgumentParser(usage=__doc__)
    ap.add_argument('job')
    ap.add_argument('--minutes', type=float, default=60)
    a = ap.parse_args()
    deadline = time.monotonic() + a.minutes * 60
    last = None
    while True:
        try:
            job = next((j for j in jobs() if j['name'] == a.job), None)
        except urllib.error.HTTPError as e:
            # GitHub also uses 403 for rate limiting.
            headers = e.headers or {}
            retryable = e.code in (408, 429) or e.code >= 500 or (
                e.code == 403 and (headers.get('Retry-After') or headers.get('X-RateLimit-Remaining') == '0'))
            print(f'jobs: {e}', flush=True)
            if not retryable:
                return 1
            job = None
        except (OSError, ValueError, KeyError) as e:  # the API had a moment; ask again
            print(f'jobs: {e}', flush=True)
            job = None
        state = (job['status'], job['conclusion']) if job else ('not found', None)
        if state != last:
            print(f'{a.job}: {state[0]}' + (f', {state[1]}' if state[1] else ''), flush=True)
            last = state
        if job and job['status'] == 'completed':
            return 0 if job['conclusion'] == 'success' else 1
        if time.monotonic() > deadline:
            print(f'{a.job} did not finish within {a.minutes:g} minutes', flush=True)
            return 1
        time.sleep(20)


if __name__ == '__main__':
    sys.exit(main())
