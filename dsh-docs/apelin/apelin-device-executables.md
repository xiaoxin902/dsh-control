
# Running a program you built

This is for an executable you compile and run yourself through
shell_run: a helper, a converter, a test program. A tool meant to
stay goes in a package instead: a cli project
(apelin-project-description), whose build signs it for you, or a
workspace's build script (apelin-external-build).

## Sign it, every time you link it
A binary the toolchain linked and nothing signed is killed as it
starts: shell_run answers exit 137 with no output. Sign it with ldid
and this skill's entitlements before the first run, and again after
every link, since a link writes a new file:
1. Read this skill's file `Tool.entitlements` (apelin_skill_read with
   that file) and write it once beside the program, such as
   `tools/Tool.entitlements`; never over a cli project's
   `Packaging/Tool.entitlements`, which its build signs with.
2. Sign: `{"argv": ["ldid", "-STool.entitlements", "converter"],
   "cwd": "tools"}`, the file joined to `-S` with no space.
3. Run it with `command` and the same `cwd` (`./converter in.mp4
   out.gif`): an argv takes only a name on the search path, never a
   path.

Give the compiler and ldid paths relative to the working directory,
as the apelin-bootstrap-paths skill says for roothide. The
environment section says whether ldid is on shell_run's PATH; when
it is not, nothing here can sign your program, so tell the user
rather than running it unsigned.

## The GPU and media frameworks
A bootstrap withholds the IOKit user clients of the GPU, IOSurface and
the media accelerators from an ad-hoc signed binary until its
entitlements name them. A program signed without them starts, then
fails inside the framework. On a device, a converter that decoded
with VideoToolbox kept getting -6662 (`kCVReturnAllocationFailed`)
from `CVPixelBufferCreate` because no IOSurface could be made;
rewriting the decoder did not help, and signing it with these
classes did. `Tool.entitlements` carries the cli template's keys,
these classes among them under both spellings of the key,
`com.apple.security.iokit-user-client-class` and
`com.apple.security.exception.iokit-user-client-class`. So when a
media or GPU call fails in a program you signed some other way, sign
it again with this file and run it again before changing the code.

A cli project's tool is signed with the file its product's
`entitlements` names. The template writes both lists into it from
version 0.1.1 of the command-line tool extension (the `version`
under `template` in `apelin-project.json`). A project keeps the file
it was made with, so one made from 0.1.0 has neither; if it uses
these frameworks, copy both lists into that file from this skill's.
That changes the build description, so Strict mode asks before its
next build.

Files in this skill's folder (apelin_skill_read with file): Tool.entitlements
