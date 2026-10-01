# CEF for Windows ARM64EC (branch 5112)

This branch builds CEF as a Windows **ARM64EC** binary, with the V8 JIT
enabled, based on:

| Component | Revision |
|---|---|
| CEF | branch `5112`, version `104.4.26+g4180781` |
| Chromium | `104.0.5112.102` |
| Clang | `llvmorg-21-init-16348-gbd809ffb-13` (set by the patches) |

ARM64EC binaries run natively on Windows on ARM and can be loaded by, and can
load, x64 code in the same process. The build is a static (non-component)
build, like the official CEF releases.

The changes come in two parts:

- **CEF source changes** are commits on this branch (build configuration,
  test app settings).
- **Chromium, V8 and third-party changes** are the patches in
  [`patches/`](patches/), one per git repository, applied with
  [`apply_arm64ec_patches.bat`](apply_arm64ec_patches.bat).

## Prerequisites

- Windows 11 on ARM64 (an x64 build machine also works)
- Visual Studio 2022 with "Desktop development with C++" and the MSVC v143
  **ARM64/ARM64EC** build tools
- Windows SDK **10.0.26100.0**
- [depot_tools](https://chromium.googlesource.com/chromium/tools/depot_tools.git)
- CEF's [`automate-git.py`](https://github.com/chromiumembedded/cef/blob/master/tools/automate/automate-git.py)
- About 150 GB of free disk space, and several hours of build time

## Build

The commands below use `C:\code` as the working directory.

### 1. Check out Chromium and this branch

`automate-git.py` needs a numeric `--branch` (it selects the Chromium version)
and takes this branch through `--checkout`:

```cmd
set DEPOT_TOOLS_WIN_TOOLCHAIN=0
python automate-git.py --download-dir=C:\code\chromium_git ^
  --depot-tools-dir=C:\code\depot_tools ^
  --url=https://github.com/Multicorewareinc/cef.git ^
  --branch=5112 --checkout=origin/5112_arm64ec ^
  --no-build --no-distrib --arm64-build
```

This fetches Chromium `104.0.5112.102`, copies this branch to
`C:\code\chromium_git\chromium\src\cef` and applies CEF's own Chromium patches.

### 2. Apply the ARM64EC patches

```cmd
set PATH=C:\code\depot_tools;%PATH%
cd C:\code\chromium_git\chromium\src\cef\arm64ec
apply_arm64ec_patches.bat check
apply_arm64ec_patches.bat apply
```

`check` is a dry run. The script finds `chromium\src` from its own location;
pass a path as the second argument to use a different one. Patches that are
already applied are skipped, and `revert` undoes them. The log is written to
`%TEMP%\arm64ec_patch_<mode>.log`.

### 3. Download Clang 21

The patches switch the toolchain to Clang 21, but the checkout already
downloaded the old Clang:

```cmd
cd C:\code\chromium_git\chromium\src
python3 tools\clang\scripts\update.py
```

### 4. Fix the Windows SDK header (one-time, outside the source tree)

Clang rejects a constant expression in the SDK's `dxva.h`. In
`C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um\dxva.h`, replace

```c
#define DXVABitMask(__n) (~((~0) << __n))
```

with

```c
#define DXVABitMask(__n) (~((~0U) << (__n)))
```

### 5. Generate the build files and build

`create.bat` sets `CEF_ENABLE_ARM64=1`, `CEF_ENABLE_ARM64EC=1` and the GN
defines for a static build, then runs `cef_create_projects.bat`:

```cmd
cd C:\code\chromium_git\chromium\src\cef
create.bat
cd ..
ninja -C out\Release_GN_arm64 cefsimple ceftests
```

A full build is about 68,000 steps (about 5 hours on a Snapdragon X Elite) and
needs about 60 GB in `out\Release_GN_arm64`. `libcef.dll` is about 225 MB and
`libcef.dll.pdb` about 4.3 GB.

### 6. Run

```cmd
out\Release_GN_arm64\cefsimple.exe
```

No command-line flags are needed. The JIT is enabled, and the test apps turn
the sandbox off themselves on ARM64EC.

### 7. Package

Create a client distribution with the same layout as the official CEF
`..._client` packages:

```cmd
cd C:\code\chromium_git\chromium\src\cef\tools
set CEF_ENABLE_ARM64=1
set CEF_ENABLE_ARM64EC=1
python3 make_distrib.py --output-dir=C:\code\binary_distrib --ninja-build ^
  --arm64-build --client --no-symbols --no-docs
```

This produces
`cef_binary_104.4.26+g4180781+chromium-104.0.5112.102_windowsarm64ec_client.tar.bz2`.
On arm64, CEF 5112 packages `cefsimple.exe` as the client application. Do not
run the app from inside the package folder before archiving it; it creates a
`GPUCache` folder there.

## Using the binaries in your application

- **Disable the sandbox.** The sandboxed renderer process crashes on ARM64EC.
  Set `CefSettings.no_sandbox = true` (or pass `--no-sandbox`).
- Build your application as ARM64EC or x64. Native ARM64 processes cannot load
  ARM64EC DLLs.

## What the changes do

| Where | Change |
|---|---|
| `tools/gn_args.py`, `create.bat` | Build the arm64 configurations as ARM64EC (`cef_enable_arm64ec`), static |
| `include/base/cef_build.h` | Detect ARM64EC as ARM64 (`_M_X64` is also defined for ARM64EC) |
| `BUILD.gn` | Link `libcef.dll` with `/pdbpagesize:8192`; its PDB is over 4 GiB |
| `tools/make_distrib.py` | Name packages `windowsarm64ec` |
| `tests/cefsimple`, `tests/ceftests`, `tests/cefclient` | Disable the sandbox on ARM64EC |
| `patches/chromium_src.patch` | ARM64EC macro guards, GN/toolchain support, Clang 21 upgrade and fixes, crashpad ARM64EC context object, pre-generated ARM64 MIDL outputs, and the fixes below |
| `patches/v8.patch` | ARM64EC support in V8: macros, EC-code memory, unwinding, sampler, calls from JIT code into C++ |
| `patches/third_party_*.patch`, `net_*`, `buildtools_*` | ARM64EC macro guards and Clang 21 fixes in each dependency |

Fixes that go beyond macro guards and build settings:

- **JIT memory.** On ARM64EC, executable memory must be allocated with
  `MEM_EXTENDED_PARAMETER_EC_CODE`, or Windows treats the generated ARM64 code
  as x64 code. Inside CEF, V8 allocates through gin and PartitionAlloc, so
  `page_allocator_internals_win.h` sets the flag on every reserve and commit
  (code pages are recommitted as the GC reuses them). V8's own allocator in
  `platform-win32.cc` also sets it for memory reserved for JIT code.
- **Static MSVC C++ runtime.** `libcpmt.lib` references
  `__sanitizer_annotate_contiguous_container` and relies on `/alternatename`
  to fall back to a no-op. lld does not apply that to ARM64EC symbols, so
  `build/config/win/arm64ec_sanitizer_stubs.cc` provides the no-op.
- **Startup stack overflow.** `ScopedHandleVerifier` compared
  `GetProcAddress(exe, "GetHandleVerifier")` with its own function address.
  On ARM64EC, `GetProcAddress` returns the export's x64 entry thunk, so the
  check never matched and the exe called itself recursively. It now compares
  modules on ARM64EC.

## Notes

- Do not re-run `automate-git.py` with `--force-clean` or `--force-update`
  after applying the patches. It resets the checkout, and the patches have to
  be applied again.
- Running `create.bat` again is safe; it only regenerates the build files.
