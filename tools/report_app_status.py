#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the Markdown survey and refresh per-app notes from captured evidence."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import quote


def link(path, label):
    return '['+label+']('+quote(path, safe='/.-')+')'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--import-root', type=Path)
    ap.add_argument('--analyze-only', action='store_true')
    ap.add_argument('--import-tool', type=Path, default=Path('bazel-bin/macho_import_report'))
    args = ap.parse_args()
    workspace = Path.cwd()
    manifest = workspace / 'docs/app-results/results.json'
    data = json.loads(manifest.read_text())
    rows = data['apps']
    if args.import_root:
        cache_path = workspace / '.cache/import-report-cache.json'
        cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
        if cache.get('root_sha256') != data['root_sha256']:
            cache = dict(root_sha256=data['root_sha256'], entries={})
        for row in rows:
            if row['kind'] != 'vendor' or not row['executable_present']:
                continue
            image = workspace / row['source'] / 'Contents/MacOS' / row['executable']
            row['import_report'] = f"docs/app-results/{row['id']}-imports.txt"
            previous = cache['entries'].get(row['id'], {})
            if previous.get('sha256') == row['executable_sha256'] and Path(row['import_report']).is_file():
                output = Path(row['import_report']).read_text()
                row['import_report_exit_status'] = previous['exit_status']
            else:
                result = subprocess.run([str(args.import_tool), '--root', str(args.import_root), str(image)],
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                output = result.stdout.decode(errors='replace').replace(str(workspace)+'/', '')
                Path(row['import_report']).write_text(output.rstrip()+'\n')
                row['import_report_exit_status'] = result.returncode
                cache['entries'][row['id']] = dict(sha256=row['executable_sha256'], exit_status=result.returncode)
            missing = re.findall(r'^  NO\s+\d+/\d+\s+(.+)$', output, re.M)
            row['absent_main_dependencies'] = missing
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps(cache, indent=2)+'\n')
        if args.analyze_only:
            return
        manifest.write_text(json.dumps(data, indent=2)+'\n')
    counts = Counter(r.get('status', 'not attempted') for r in rows)
    staging = Counter(r.get('staging','not staged') for r in rows)
    intro = f"""# Current app launch survey

Captured {data['date']} (UTC) from the local checkout. The inventory contains
{len(rows)} entries: {sum(r['kind']=='vendor' for r in rows)} vendor bundles/aliases
and {sum(r['kind']=='source' for r in rows)} source app configurations. Nested
helpers and the Sparkle updater alias are separate entries. The original vendor
executables are identified by SHA-256 in [results.json](../app-results/results.json).

| Observation | Entries |
|---|---:|
"""
    intro += ''.join(f'| {status} | {count} |\n' for status,count in sorted(counts.items()))
    intro += """
Each screenshot is an unmodified QEMU framebuffer capture after that entry's
launch attempt. A desktop-only capture is evidence that no app window appeared,
not a screenshot of a functioning app. Logs record the actual loader/runtime
output. Startup windows do not establish working features, and existing
app-specific workarounds remain in the frameworks.

The survey uses temporary copies of the RAM-root image. Large bundles exceed
the complete-copy budget and receive **limited startup probes** with bundled Mach-O libraries that fit
and selected resources. Frameworks/assets can still be omitted; the manifest
records omitted native images. Such a missing bundled
library is a provisioning limit, not proof that the original bundle is incomplete.
Helpers launched in isolation may need their containing application's resources,
arguments or services. Eight seconds is the default observation bound, not a
proof that a process can never open a window. ARM64/ARM64e slices are prepared
and ad-hoc signed; originals are untouched. No new compatibility fixes were made.

| Staging scope | Entries |
|---|---:|
"""
    intro += ''.join(f'| {scope} | {count} |\n' for scope,count in sorted(staging.items()))
    intro += """
Import reports measure **only the main executable's direct imports against the
baseline guest filesystem**. `@rpath` libraries may exist in the original bundle
and still appear absent in this system-root-only analysis. Counts do not measure
Objective-C selector implementations, dynamically opened libraries, API behavior,
or a complete dependency closure. Use the runtime logs and staging scope with
the import report; none of these establishes full app compatibility.

See [PLAN.md](../../PLAN.md) for the remaining framework, runtime, service and
storage work. The older per-app pages contain focused follow-up notes.

## All entries

| Source bundle/configuration | Observation | Diagnostic excerpt | Staging | Evidence |
|---|---|---|---|---|
"""
    for row in rows:
        evidence = []
        for key, label in [('screenshot','PNG'),('log','launch log'),('import_report','imports')]:
            if row.get(key):
                evidence.append(link('../../'+row[key], label))
        stage = 'not staged' if not row.get('staging') else ('complete' if row.get('staging') == 'complete bundle copy' else ('source app' if row['kind']=='source' else '**limited probe**'))
        diagnostics = row.get('diagnostics', [])
        fatal = [d for d in diagnostics if any(s in d.lower() for s in ('cannot open', 'unsupported', 'illegal instruction', 'segmentation', 'abort trap'))]
        diagnostic = (fatal or diagnostics or [row.get('inventory_error', 'No diagnostic captured')])[0]
        diagnostic = diagnostic.replace('|', r'\|').replace('`', "'").replace('<', '&lt;').replace('>', '&gt;')
        if len(diagnostic) > 180:
            diagnostic = diagnostic[:177] + '...'
        intro += f"| `{row['source']}` | {row.get('status', 'not attempted')} | {diagnostic} | {stage} | {' · '.join(evidence)} |\n"
    Path('docs/apps/current-status.md').write_text(intro)
    Path('docs/apps/README.md').write_text(f"""# Application status and remaining work

The [current launch survey](current-status.md) covers **{len(rows)} entries** from
`apps/` and the complete recursive local `vendor/` inventory, including helpers.
It links every raw screenshot, serial log and available main-executable import
report. The machine-readable evidence is [results.json](../app-results/results.json).

Status means what was observed during a bounded startup probe. Limited staging,
missing bundles, windows rendered with existing workarounds, and untested app
features are identified explicitly. See [PLAN.md](../../PLAN.md) for the remaining
Darling work and the limits of these measurements.

The baseline demo/desktop suite is recorded separately in
[validation.md](../validation.md). Focused notes for previously evaluated apps
remain below; their previous symbol totals have been replaced by current evidence.

""" + '\n'.join('- '+link(p.name,p.stem) for p in sorted(Path('docs/apps').glob('*.md')) if p.name not in ('README.md','current-status.md'))+'\n')
    # Keep the useful follow-up work, replacing outdated versions, statuses and totals.
    for path in Path('docs/apps').glob('*.md'):
        if path.name in ('README.md','current-status.md'):
            continue
        old = path.read_text()
        heading = old.splitlines()[0]
        name = heading.removeprefix('# ').split(' (`')[0]
        alias = {'SparkleUpdater':'Updater', 'Platypus 5.5.0':'System Info', 'Platypus 5.5.0 ScriptExec':'System Info'}
        matches = [r for r in rows if r['name'].casefold() == alias.get(name,name).casefold()]
        if path.stem == 'platypus-5.5.0':
            matches = [r for r in rows if r['name'] in ('System Info','ProgressBar') and r['kind']=='source']
        work = re.search(r'## What needs to be done\n(.*?)(?=\n## |\Z)', old, re.S)
        if not work:
            work = re.search(r'## Remaining work\n(.*?)(?=\n## |\Z)', old, re.S)
        followup = work[1].strip() if work else 'See the current survey and [PLAN.md](../../PLAN.md) for the remaining platform work.'
        followup = re.sub(r'\n?\[Complete current survey\]\(current-status\.md\)\.', '', followup).strip()
        # Historical bundle-integrity claims cannot be carried across snapshots.
        followup = '\n'.join(l for l in followup.splitlines() if 'symlinks lost' not in l)
        text = '# '+name+'\n\nCurrent snapshot: '+data['date']+' (UTC).\n\n'
        if matches:
            for row in matches:
                text += f"- Source: `{row['source']}`.\n- Observation: **{row.get('status', 'not attempted')}**.\n- Staging: {row.get('staging', 'not staged')}.\n"
                if row.get('bundle_bytes') is not None:
                    text += f"- Original regular-file size: {row['bundle_bytes']/1024**2:.1f} MiB (symlinks excluded).\n"
                if row.get('native_dependency_probe_version'):
                    text += f"- Prepared Mach-O images: {row['signed_images']}; omitted native images: {len(row['omitted_macho_images'])}.\n"
                if row.get('version'):
                    text += '- Local bundle version: `'+row['version']+'`.\n'
                text += '- Evidence: '+', '.join(link('../../'+row[k], label) for k,label in [('screenshot','screenshot'),('log','launch log'),('import_report','direct-import report')] if row.get(k))+'.\n\n'
                if row.get('diagnostics'):
                    text += 'First recorded diagnostic:\n\n```text\n'+row['diagnostics'][0]+'\n```\n\n'
            text += 'The capture establishes only the observed startup state. App features were not validated by this survey; partial bundle probes cannot establish full-bundle compatibility.\n\n'
        else:
            text += 'This bundle is **absent from the current vendor inventory**. Earlier launch claims and symbol totals are not current measurements. No fresh screenshot can be attributed to it.\n\n'
        text += '## Remaining work\n\n'+followup+'\n\n[Complete current survey](current-status.md).\n'
        path.write_text(text)


if __name__ == '__main__':
    main()
