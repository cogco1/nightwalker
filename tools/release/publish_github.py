"""Publish verified source; remove older game package assets only after the new package is available."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPO = 'cogco1/nightwalker'
API = 'https://api.github.com/repos/' + REPO


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args]).strip()


def api(method, path, data=None, raw=None, content_type='application/json'):
    url = path if path.startswith('https://uploads.github.com/') else API + path
    if not (url.startswith(API + '/') or url.startswith('https://uploads.github.com/repos/' + REPO + '/')):
        raise RuntimeError('Unexpected API destination')
    headers = {'Authorization': 'Bearer ' + os.environ['GITHUB_TOKEN'],
               'Accept': 'application/vnd.github+json', 'User-Agent': 'Nightwalker-publisher',
               'X-GitHub-Api-Version': '2022-11-28'}
    body = raw if raw is not None else (json.dumps(data, ensure_ascii=False).encode() if data is not None else None)
    if body is not None:
        headers['Content-Type'] = content_type
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=180) as response:
        content = response.read()
        return json.loads(content) if content else None


def optional(path):
    try:
        return api('GET', path)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def main():
    if os.environ.get('GITHUB_REPOSITORY') != REPO or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise RuntimeError('Run only from the intended repository main branch')
    version = (ROOT / 'VERSION').read_text().strip()
    if not re.fullmatch(r'v\d{4}\.\d{2}\.\d{2}(?:\.\d+)?', version):
        raise RuntimeError('Unexpected version')
    sha = git('rev-parse', 'HEAD').decode()
    if sha != os.environ['GITHUB_SHA'] or api('GET', '/git/ref/heads/main')['object']['sha'] != sha:
        raise RuntimeError('Main has changed; publish its current commit instead')
    if git('status', '--porcelain'):
        raise RuntimeError('Source checkout is dirty')
    verified = json.loads((ROOT / 'docs/verification/combat-v07.json').read_text())
    expected_game = verified['game_tree']
    if git('rev-parse', 'HEAD:game').decode() != expected_game or not verified['passed']:
        raise RuntimeError('Game source no longer matches the verified release')
    output = Path(os.environ['RUNNER_TEMP']) / ('nightwalker-' + version)
    output.mkdir(exist_ok=True)
    archive = output / ('Nightwalker-' + version + '-source.zip')
    git('archive', '--format=zip', '--prefix=nightwalker/', '--output=' + str(archive), 'HEAD')
    entries = {}
    for record in git('ls-tree', '-rz', 'HEAD').split(b'\0'):
        if not record: continue
        metadata, path = record.split(b'\t', 1)
        mode, kind, blob_sha = metadata.split()
        if kind != b'blob':
            raise RuntimeError('Unexpected non-file tree entry')
        entries[path.decode('utf-8')] = blob_sha.decode()
    with zipfile.ZipFile(archive) as z:
        files = [n for n in z.namelist() if not n.endswith('/')]
        if {n.removeprefix('nightwalker/') for n in files} != set(entries):
            raise RuntimeError('Archive file list differs from source tree')
        for name in files:
            data = z.read(name)
            # Git archive applies the repository eol attributes to Windows launchers.
            if name.endswith(('.cmd', '.bat', '.ps1')):
                data = data.replace(b'\r\n', b'\n')
            actual = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
            if actual != entries[name.removeprefix('nightwalker/')]:
                raise RuntimeError('Archive content mismatch: ' + name)
    manifest = {'version': version, 'source_commit': sha, 'source_tree': git('rev-parse', 'HEAD^{tree}').decode(),
                'game_tree': expected_game, 'archive': archive.name, 'files': len(entries),
                'bytes': archive.stat().st_size, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                'verification': {'suites': verified['suite_count'], 'checks_passed': verified['checks']}}
    manifest_path = output / 'release-manifest.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    notes = (ROOT / 'docs/releases' / (version + '.md')).read_text(encoding='utf-8')
    release = optional('/releases/tags/' + version)
    if release is None:
        release = api('POST', '/releases', {'tag_name': version, 'target_commitish': sha,
                      'name': '夜行者 ' + version + ' · 最新版', 'body': notes, 'draft': True, 'prerelease': False})
    tag_ref = optional('/git/ref/tags/' + version)
    if tag_ref is not None and (tag_ref['object']['type'] != 'commit' or tag_ref['object']['sha'] != sha):
        raise RuntimeError('Existing version tag targets a different source')
    for path in (archive, manifest_path):
        digest = 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
        existing = next((a for a in api('GET', '/releases/' + str(release['id']) + '/assets') if a['name'] == path.name), None)
        if existing:
            if existing['state'] != 'uploaded' or existing.get('digest') != digest:
                raise RuntimeError('Existing asset differs; refusing to replace it')
            continue
        uploaded = api('POST', release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(path.name),
                       raw=path.read_bytes(), content_type='application/zip' if path.suffix == '.zip' else 'application/json')
        if uploaded['size'] != path.stat().st_size or uploaded.get('digest') != digest:
            raise RuntimeError('Uploaded asset verification failed')
    api('PATCH', '/releases/' + str(release['id']), {'draft': False, 'prerelease': False, 'make_latest': 'true'})
    tag = api('GET', '/git/ref/tags/' + version)['object']
    if tag['type'] != 'commit' or tag['sha'] != sha:
        raise RuntimeError('Published tag targets a different source')
    latest = api('GET', '/releases/latest')
    if latest['id'] != release['id'] or latest['tag_name'] != version:
        raise RuntimeError('Latest release verification failed')
    deleted = []
    # Limit cleanup to our own older source packages and their manifests; keep releases, tags and history.
    page = 1
    while True:
        releases = api('GET', '/releases?per_page=100&page=' + str(page))
        for old in releases:
            if old['id'] == release['id'] or old['draft']:
                continue
            if not re.fullmatch(r'v\d{4}\.\d{2}\.\d{2}(?:\.\d+)?', old['tag_name']) or old['tag_name'] >= version:
                continue
            assets = api('GET', '/releases/' + str(old['id']) + '/assets')
            package_name = 'Nightwalker-' + old['tag_name'] + '-source.zip'
            if not any(asset['name'] == package_name for asset in assets):
                continue
            for asset in assets:
                if asset['name'] not in [package_name, 'release-manifest.json']:
                    continue
                api('DELETE', '/releases/assets/' + str(asset['id']))
                deleted.append({'release': old['tag_name'], 'asset': asset['name']})
        if len(releases) < 100:
            break
        page += 1
    if api('GET', '/git/ref/heads/main')['object']['sha'] != sha:
        raise RuntimeError('Main changed during publication')
    result = {'release': latest['html_url'], 'manifest': manifest, 'deleted_old_package_assets': deleted}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as summary:
        summary.write('Published [' + version + '](' + latest['html_url'] + ') as Latest.\n\n')
        summary.write('Source commit: `' + sha + '`. Verified ' + str(len(entries)) + ' archive files.\n\n')
        summary.write('Removed ' + str(len(deleted)) + ' older package assets after verifying the new download.\n')


if __name__ == '__main__':
    main()
