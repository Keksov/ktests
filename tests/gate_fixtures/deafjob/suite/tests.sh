#!/usr/bin/env bash
# gate fixture "deafjob" (launch L2.7-G): the cell's runner itself stops
# hearing cygwin signals — the wrapper writes "PID WINPID" to
# TMPDIR/gfx-deafjob.pid and has powershell suspend its own Windows process
# (NtSuspendProcess: its cygwin signal thread never runs again, TERM and KILL
# are lost). The gate's stop after --timeout must end it from the Windows side
# (`kill -f`, taskkill), or its `wait` for the job never returns. Safety
# net: a hidden powershell (no cygwin process) ends it after 120 s if it is
# still the process suspended (the same start time) and nothing else did.
# Cygwin only: elsewhere the fixture is a plain pass.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r /proc/$BASHPID/winpid ]]; then
    read -r __gfx_w < "/proc/$BASHPID/winpid"
    if [[ "$__gfx_w" =~ ^[0-9]+$ ]]; then
        printf '%s %s\n' "$BASHPID" "$__gfx_w" > "${TMPDIR:-/tmp}/gfx-deafjob.pid"
        __gfx_ps="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null)/System32/WindowsPowerShell/v1.0/powershell.exe"
        [[ -x "$__gfx_ps" ]] || __gfx_ps=powershell.exe
        # The compile writes into %TEMP%: a Windows TEMP/TMP of its own (a bash
        # started from the other runtime may have none: then C:\Windows, denied).
        # .NET calls only, no cmdlet: a cmdlet's module autoload took 22-30 s
        # on windows-latest without the image's PSModuleAnalysisCachePath
        # (which a gate cell does not pass) — past this cell's 5 s (057)
        __gfx_tw="$(cygpath -w "${TMPDIR:-/tmp}" 2>/dev/null)"
        MSYS2_ARG_CONV_EXCL='*' TEMP="$__gfx_tw" TMP="$__gfx_tw" "$__gfx_ps" -NoProfile -NonInteractive -Command "\$o=[System.CodeDom.Compiler.CompilerParameters]::new(); \$o.GenerateInMemory=\$true; \$k=[Microsoft.CSharp.CSharpCodeProvider]::new().CompileAssemblyFromSource(\$o,'public static class KtW { [System.Runtime.InteropServices.DllImport(\"ntdll.dll\")] public static extern int NtSuspendProcess(System.IntPtr h); }').CompiledAssembly.GetType('KtW'); \$p=[Diagnostics.Process]::GetProcessById($__gfx_w); \$t=\$p.StartTime.Ticks; [void]\$k::NtSuspendProcess(\$p.Handle); \$s=[Diagnostics.ProcessStartInfo]::new('powershell.exe',('-NoProfile -NonInteractive -Command try{\$q=[Diagnostics.Process]::GetProcessById($__gfx_w)}catch{exit}; if(\$q.StartTime.Ticks -eq ' + \$t + ' -and -not \$q.WaitForExit(120000)){ \$q.Kill() }')); \$s.WindowStyle='Hidden'; [void][Diagnostics.Process]::Start(\$s)" </dev/null >/dev/null 2>&1
    fi
fi
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture deafjob" "$@"
