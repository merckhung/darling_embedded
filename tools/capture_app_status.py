#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Inventory and launch every local app under QEMU; retain failures as evidence.

This is a host-side measurement tool, not a compatibility implementation. Copies
are thinned/re-signed for Cortex-A72; original vendor bundles are never modified.
Large bundles receive explicitly labelled launcher-only probes on the RAM root.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import select
import shlex
import shutil
import socket
import struct
import subprocess
import tempfile
import time


def sanitize(text):
    text = text.replace(str(Path.cwd()), '<workspace>').replace('\x00', '<NUL>')
    text = re.sub(r'/(?:[^/\s:]+/)*execroot/_main(?=[/\s:]|$)', '<build-root>', text)
    text = re.sub(r'/(?:[^/\s:]+/)*(?:Users|home)/[^/\s:]+', '<home>', text)
    return '\n'.join(line.rstrip() for line in text.replace('\r', '').splitlines()).rstrip() + '\n'


def run(*args, check=True):
    result = subprocess.run([str(x) for x in args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode(errors='replace')
    if check and result.returncode:
        raise RuntimeError('Command failed: '+str(args)+'\n'+output[-4000:])
    return output


def inventory(workspace):
    rows = []
    for bundle in sorted((workspace / 'vendor').rglob('*.app')):
        if not bundle.is_dir() or bundle.name.startswith('._'):
            continue
        rel = bundle.relative_to(workspace).as_posix()
        row = dict(source=rel, name=bundle.stem, kind='vendor')
        row['id'] = re.sub('[^a-z0-9]+', '-', bundle.stem.lower()).strip('-') + '-' + hashlib.sha256(rel.encode()).hexdigest()[:8]
        try:
            info = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
            row['executable'] = info.get('CFBundleExecutable', '')
            row['version'] = str(info.get('CFBundleShortVersionString', info.get('CFBundleVersion', 'unknown')))
            exe = bundle / 'Contents/MacOS' / row['executable']
            row['executable_present'] = bool(row['executable']) and exe.is_file()
            row['executable_sha256'] = hashlib.sha256(exe.read_bytes()).hexdigest() if row['executable_present'] else None
        except (OSError, ValueError, plistlib.InvalidFileException) as e:
            row.update(executable='', executable_present=False, inventory_error=type(e).__name__)
        rows.append(row)
    for name, source in [('HelloWorld', 'apps/HelloWorld'), ('WidgetGallery', 'apps/WidgetGallery'),
                         ('System Info', 'apps/PlatypusApps/System Info'), ('ProgressBar', 'apps/PlatypusApps/ProgressBar')]:
        rows.append(dict(id=re.sub('[^a-z0-9]+', '-', name.lower()), name=name, source=source,
                         kind='source', executable=name, executable_present=True))
    return rows


class Guest:
    def __init__(self, args, root, work):
        self.log = ''
        self.work = work
        physical = json.loads(args.layout.read_text())['physical_base']
        physical = int(physical, 0) if isinstance(physical, str) else physical
        (work / 'entropy').write_bytes(os.urandom(256))
        (work / 'hosttime').write_bytes(b'HOSTTIME' + struct.pack('<Q', int(time.time())))
        sock = work / 'qmp.sock'
        command = ['qemu-system-aarch64', '-M', 'raspi4b', '-cpu', 'cortex-a72', '-m', '2G',
                   '-display', 'none', '-serial', 'stdio', '-monitor', 'none', '-no-reboot',
                   '-qmp', f'unix:{sock},server=on,wait=off']
        for item in [f'loader,file={args.loader},addr=0x40080000,cpu-num=0',
                     'loader,addr=0x40070000,data=0x17ffffffd503207f,data-len=8',
                     *[f'loader,addr=0x40070000,cpu-num={n}' for n in (1, 2, 3)],
                     f'loader,file={args.kernel},addr={hex(physical)}',
                     f'loader,file={work / "entropy"},addr=0x07f00000',
                     f'loader,file={work / "hosttime"},addr=0x07f00800',
                     f'loader,file={root},addr=0x0a000000',
                     'usb-hub,id=native-hub', 'usb-kbd,port=1.1', 'usb-mouse,port=1.2',
                     'usb-net,netdev=n0,port=1.3']:
            command += ['-device', item]
        for prop in ['xres=1024', 'yres=768', 'bpp=32', 'pixo=0']:
            command += ['-global', 'bcm2835-fb.' + prop]
        command += ['-netdev', 'user,id=n0']
        self.proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        os.set_blocking(self.proc.stdout.fileno(), False)
        self.qmp = socket.socket(socket.AF_UNIX)
        self.qmp.settimeout(10)
        for _ in range(100):
            try:
                self.qmp.connect(str(sock))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                if self.proc.poll() is not None:
                    raise RuntimeError('QEMU exited before QMP connection')
                time.sleep(.1)
        self.qfile = self.qmp.makefile('rb')
        self.qfile.readline()
        self.command('qmp_capabilities')
        if not self.wait('DARLING_SHELL_READY:', 150):
            self.close()
            raise RuntimeError('Guest desktop did not start: ' + self.log[-2000:])
        self.pump(2)

    def command(self, cmd, arguments=None):
        payload = dict(execute=cmd)
        if arguments is not None:
            payload['arguments'] = arguments
        self.qmp.sendall((json.dumps(payload) + '\n').encode())
        while True:
            response = json.loads(self.qfile.readline())
            if 'error' in response:
                raise RuntimeError(str(response))
            if 'return' in response:
                return response['return']

    def pump(self, seconds):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            if select.select([self.proc.stdout], [], [], min(.1, max(0, until-time.monotonic())))[0]:
                data = os.read(self.proc.stdout.fileno(), 65536)
                if data:
                    self.log += data.decode(errors='replace')
                elif self.proc.poll() is not None:
                    break

    def send(self, text):
        self.proc.stdin.write((text+'\n').encode())
        self.proc.stdin.flush()

    def wait(self, marker, seconds, start=0):
        until = time.monotonic() + seconds
        while marker not in self.log[start:] and time.monotonic() < until and self.proc.poll() is None:
            self.pump(.1)
        return marker in self.log[start:]

    def screenshot(self, dest):
        ppm = self.work / 'screen.ppm'
        self.command('screendump', dict(filename=str(ppm)))
        # Preserve the raw framebuffer. No labels, synthetic error dialogs or overlays.
        if shutil.which('pnmtopng'):
            with dest.open('wb') as out:
                subprocess.run(['pnmtopng', str(ppm)], stdout=out, stderr=subprocess.PIPE, check=True)
        else:
            run('convert', ppm, dest)
        return hashlib.sha256(dest.read_bytes()).hexdigest()

    def close(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        self.qmp.close()


def provision(row, args, stage):
    if row['kind'] == 'source':
        row['guest_bundle'] = '/Applications/' + row['name'] + '.app'
        row['staging'] = 'built from source (Platypus apps use official ScriptExec)'
        return 0
    source = args.workspace / row['source']
    dest = stage / 'Applications' / row['id'] / source.name
    row['guest_bundle'] = '/Applications/' + row['id'] + '/' + source.name
    size = sum(p.stat().st_size for p in source.rglob('*') if p.is_file() and not p.is_symlink())
    row['bundle_bytes'] = size
    if size <= args.bundle_limit * 1024**2:
        shutil.copytree(source, dest, symlinks=True)
        row['staging'] = 'complete bundle copy'
    else:
        row['staging'] = 'launcher and selected UI resources only (bundle exceeds RAM-root probe budget)'
        (dest / 'Contents/MacOS').mkdir(parents=True)
        for sub in ['Info.plist', 'PkgInfo']:
            if (source / 'Contents' / sub).is_file():
                shutil.copyfile(source / 'Contents' / sub, dest / 'Contents' / sub)
        if row['executable_present']:
            shutil.copyfile(source / 'Contents/MacOS' / row['executable'], dest / 'Contents/MacOS' / row['executable'])
        # Nibs, storyboards, strings and icons are small enough for startup probes.
        resources = source / 'Contents/Resources'
        if resources.is_dir():
            for p in resources.rglob('*'):
                if p.is_file() and not p.is_symlink() and p.stat().st_size < 2*1024**2 and p.suffix in ['.nib', '.plist', '.strings', '.icns', '.rtf', '.loctable']:
                    target = dest / p.relative_to(source)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(p, target)
    signed = 0
    # Sign each Mach-O in the staged copy, including bundled libraries/helpers.
    for p in dest.rglob('*'):
        if not p.is_file() or p.is_symlink():
            continue
        with p.open('rb') as f:
            magic = f.read(4)
        if magic not in [b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf']:
            continue
        p.chmod(0o755)
        result = subprocess.run([str(args.signer), str(p)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if result.returncode:
            row.setdefault('signing_errors', []).append(str(p.relative_to(dest))+': '+result.stdout.decode(errors='replace')[-300:])
        else:
            signed += 1
    if row['staging'].startswith('launcher and'):
        row['staging'] = 'launcher, bundled Mach-O images and selected resources (partial bundle)'
        row['native_dependency_probe_version'] = 1
        row['omitted_macho_images'] = []
        budget = 250 * 1024**2
        used = sum(p.stat().st_size for p in dest.rglob('*') if p.is_file() and not p.is_symlink())
        framework_dir = source / 'Contents/Frameworks'
        native = []
        resources = []
        links = []
        if framework_dir.is_dir():
            for p in framework_dir.rglob('*'):
                if p.is_symlink():
                    links.append(p)
                elif p.is_file():
                    with p.open('rb') as f:
                        magic = f.read(4)
                    if magic in [b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf']:
                        native.append(p)
                    elif p.suffix in ['.plist', '.dat', '.pak', '.bin', '.nib', '.strings', '.icns'] and p.stat().st_size < 16*1024**2:
                        resources.append(p)
        # Framework binaries first, then their supporting libraries and small assets.
        def priority(p):
            framework = any(parent.suffix == '.framework' and parent.stem == p.name for parent in p.parents)
            return (not framework, -p.stat().st_size)
        for p in sorted(native, key=priority):
            target = dest / p.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, target)
            target.chmod(0o755)
            result = subprocess.run([str(args.signer), str(target)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            size = target.stat().st_size
            if used + size > budget:
                row['omitted_macho_images'].append(p.relative_to(source).as_posix())
                target.unlink()
            else:
                used += size
                if result.returncode:
                    row.setdefault('signing_errors', []).append(p.relative_to(source).as_posix()+': '+result.stdout.decode(errors='replace')[-300:])
                else:
                    signed += 1
        row['omitted_resource_files'] = 0
        for p in sorted(resources, key=lambda p: (p.suffix != '.dat', -p.stat().st_size)):
            target = dest / p.relative_to(source)
            if used + p.stat().st_size > budget:
                row['omitted_resource_files'] += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, target)
            used += p.stat().st_size
        for p in links:
            target = dest / p.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists() and not target.is_symlink():
                target.symlink_to(os.readlink(p))
    row['signed_images'] = signed
    return sum(p.stat().st_size for p in dest.rglob('*') if p.is_file() and not p.is_symlink())


def probe(row, guest, args):
    row['captured_at_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    start = len(guest.log)
    bundle = shlex.quote(row['guest_bundle'])
    # Direct darling exec preserves process identity and the real launch exit status.
    guest.send(f"(/usr/bin/darling open {bundle} & child=$!; echo PROBE_CHILD:$child; wait $child; echo PROBE_EXIT_{row['id']}:$?) & PROBE_PID=$!")
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        guest.pump(.1)
        log = guest.log[start:]
        if re.search(r'PROBE_EXIT_'+re.escape(row['id'])+r':\d+', log):
            break
        if 'DARLING_WINDOW_READY:' in log:
            guest.pump(2)
            break
    guest.pump(.5)
    row['screenshot'] = f"docs/screenshots/apps/{row['id']}.png"
    row['screenshot_sha256'] = guest.screenshot(args.workspace / row['screenshot'])
    log = guest.log[start:]
    exit_status = re.search(r'PROBE_EXIT_'+re.escape(row['id'])+r':(\d+)', log)
    row['exit_status'] = int(exit_status[1]) if exit_status else None
    windows = re.findall(r'DARLING_WINDOW_READY:([^\r\n]+)', log)
    row['windows'] = windows
    if not row['executable_present']:
        row['status'] = 'missing executable or metadata'
    elif windows:
        row['status'] = 'window observed (functionality unverified)'
    elif exit_status:
        row['status'] = 'exited without a window'
    else:
        row['status'] = 'no window within observation period'
    errors = [line for line in log.splitlines() if any(s in line.lower() for s in ['cannot open', 'undefined', 'unresolved', 'error', 'not found', 'bad cpu', 'illegal', 'segmentation', 'abort', 'failed', 'not implemented', 'unsupported', 'unrecognized'])]
    row['diagnostics'] = [sanitize(e) for e in errors[:25]]
    child = re.search(r'PROBE_CHILD:(\d+)', log)
    if child:
        guest.send('kill -9 '+child[1]+' $PROBE_PID 2>/dev/null; wait $PROBE_PID 2>/dev/null; echo PROBE_CLEANUP')
    else:
        raise RuntimeError('Missing app PID: '+log[-1000:])
    guest.pump(1)
    log = guest.log[start:]
    row['log'] = f"docs/app-results/{row['id']}.log"
    (args.workspace / row['log']).write_text(sanitize(log))
    print(row['source']+': '+row['status'], flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--workspace', type=Path, default=Path.cwd())
    for name in ['root', 'loader', 'kernel', 'layout', 'hfs', 'signer']:
        ap.add_argument('--'+name, type=Path, required=True)
    ap.add_argument('--seconds', type=float, default=8)
    ap.add_argument('--bundle-limit', type=int, default=40, help='MiB per complete bundle; larger bundles get limited probes')
    ap.add_argument('--batch-limit', type=int, default=180, help='MiB staged per guest boot')
    ap.add_argument('--match', default='')
    ap.add_argument('--resume', action='store_true')
    args = ap.parse_args()
    args.workspace = args.workspace.resolve()
    for name in ['root', 'loader', 'kernel', 'layout', 'hfs', 'signer']:
        setattr(args, name, getattr(args, name).resolve())
    out = args.workspace / 'docs/app-results'
    out.mkdir(parents=True, exist_ok=True)
    (args.workspace / 'docs/screenshots/apps').mkdir(parents=True, exist_ok=True)
    rows = inventory(args.workspace)
    manifest = out / 'results.json'
    root_sha = hashlib.sha256(args.root.read_bytes()).hexdigest()
    previous_data = json.loads(manifest.read_text()) if args.resume and manifest.exists() else {}
    previous = {r['source']:r for r in previous_data.get('apps', [])} if previous_data.get('root_sha256') == root_sha else {}
    for i, row in enumerate(rows):
        if row['source'] in previous and previous[row['source']].get('executable_sha256') == row.get('executable_sha256') and previous[row['source']].get('status') and not previous[row['source']].get('staging', '').startswith('launcher and') and (args.workspace / previous[row['source']].get('screenshot', 'absent')).is_file():
            rows[i] = previous[row['source']]
    def save():
        manifest.write_text(json.dumps(dict(date=time.strftime('%Y-%m-%d', time.gmtime()),
            root_sha256=root_sha, observation_seconds=args.seconds,
            bundle_limit_mib=args.bundle_limit, apps=rows), indent=2)+'\n')
    pending = [r for r in rows if not r.get('status') and args.match in r['source']]
    while pending:
        with tempfile.TemporaryDirectory(prefix='darling-app-probes-') as tmp:
            work = Path(tmp)
            stage = work / 'stage'
            (stage / 'Applications').mkdir(parents=True)
            batch = []
            total = 0
            while pending and total < args.batch_limit*1024**2:
                row = pending.pop(0)
                added = provision(row, args, stage)
                if batch and total + added > args.batch_limit*1024**2:
                    shutil.rmtree(stage / 'Applications' / row['id'])
                    pending.insert(0, row)
                    break
                total += added
                batch.append(row)
            image = work / 'root.img'
            shutil.copyfile(args.root, image)
            image.chmod(0o600)
            # Chromium's large binary is unnecessary for app launch probes.
            run(args.hfs, image, 'rmall', '/usr/local/chromium', check=False)
            run(args.hfs, image, 'rm', '/bin/headless_shell', check=False)
            links = [(p, os.readlink(p)) for p in stage.rglob('*') if p.is_symlink()]
            executable_paths = [p for p in stage.rglob('*') if p.is_file() and not p.is_symlink() and p.stat().st_mode & 0o111]
            for path, _ in links:
                path.unlink()
            run(args.hfs, image, 'addall', stage, '/')
            for path, target in links:
                run(args.hfs, image, 'symlink', '/' + path.relative_to(stage).as_posix(), target)
            for path in executable_paths:
                run(args.hfs, image, 'chmod', '755', '/' + path.relative_to(stage).as_posix())
            print(f'Booting batch: {len(batch)} entries, {total // 1024**2} MiB staged', flush=True)
            guest = Guest(args, image, work)
            try:
                for row in batch:
                    probe(row, guest, args)
                    save()
                (out / ('boot-'+batch[0]['id']+'.log')).write_text(sanitize(guest.log[:guest.log.find('DARLING_SHELL_READY:')+200]))
            finally:
                guest.close()
    save()


if __name__ == '__main__':
    main()
