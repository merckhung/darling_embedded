# SPDX-License-Identifier: GPL-3.0-or-later
"""Bazel repository rules for fetching and patching @darwin_embedded and @darling."""

def _run(ctx, args):
    result = ctx.execute(args, timeout = 3600, quiet = True)
    if result.return_code:
        fail("%s\n%s\n%s" % (args, result.stdout, result.stderr))

def _darwin_embedded_repository_impl(ctx):
    git = ctx.which("git")
    if not git:
        fail("git must be on PATH")
    cache = ctx.os.environ.get("DARWIN_EMBEDDED_GIT_CACHE", "")
    source = cache if cache else ctx.attr.remote
    clone = [str(git), "clone", "--no-checkout"]
    if cache:
        clone.append("--shared")
    clone.extend([source, "."])
    _run(ctx, clone)
    _run(ctx, [str(git), "-c", "filter.lfs.smudge=", "-c", "filter.lfs.process=", "-c", "filter.lfs.required=false", "checkout", "--detach", ctx.attr.commit])
    _run(ctx, [str(git), "lfs", "install", "--local"])
    if cache and ctx.path(cache + "/.git/lfs").exists:
        ctx.delete(".git/lfs")
        ctx.symlink(cache + "/.git/lfs", ".git/lfs")
    else:
        _run(ctx, [str(git), "lfs", "pull", "--include=userland/apps/chromium/prebuilt/arm64/*"])
    _run(ctx, [str(git), "lfs", "checkout", "userland/apps/chromium/prebuilt/arm64/headless_shell"])
    for patch in ctx.attr.patches:
        ctx.read(patch)
        _run(ctx, [str(git), "apply", "--whitespace=nowarn", str(ctx.path(patch))])
    ctx.file("UPSTREAM_COMMIT", ctx.attr.commit + "\n")

darwin_embedded_repository = repository_rule(
    implementation = _darwin_embedded_repository_impl,
    attrs = {
        "remote": attr.string(mandatory = True),
        "commit": attr.string(mandatory = True),
        "patches": attr.label_list(allow_files = True),
    },
    environ = ["DARWIN_EMBEDDED_GIT_CACHE"],
)

def _darling_repository_impl(ctx):
    git = ctx.which("git")
    if not git:
        fail("git must be on PATH")
    cache = ctx.os.environ.get("DARLING_GIT_CACHE", "")
    source = cache if cache else ctx.attr.remote
    clone = [str(git), "clone", "--no-checkout"]
    if cache:
        clone.append("--shared")
    clone.extend([source, "."])
    _run(ctx, clone)
    _run(ctx, [str(git), "sparse-checkout", "set", "--no-cone", "/LICENSE", "/README.md", "/src/tools/**"])
    _run(ctx, [str(git), "checkout", "--detach", ctx.attr.commit])
    for patch in ctx.attr.patches:
        ctx.read(patch)
        _run(ctx, [str(git), "apply", "--whitespace=nowarn", str(ctx.path(patch))])
    ctx.file("UPSTREAM_COMMIT", ctx.attr.commit + "\n")
    ctx.file(
        "BUILD.bazel",
        """# SPDX-License-Identifier: GPL-3.0-or-later
package(default_visibility = ["//visibility:public"])

exports_files([
    "LICENSE",
    "README.md",
    "UPSTREAM_COMMIT",
    "src/tools/sw_vers.c",
    "src/tools/open.m",
])

filegroup(
    name = "tools_sources",
    srcs = glob(["src/tools/**"]),
)
""",
    )

darling_repository = repository_rule(
    implementation = _darling_repository_impl,
    attrs = {
        "remote": attr.string(mandatory = True),
        "commit": attr.string(mandatory = True),
        "patches": attr.label_list(allow_files = True),
    },
    environ = ["DARLING_GIT_CACHE"],
)
