#!/usr/bin/env bash
# gate fixture "deaf" (launch L2.7-G): the wrapper leaves a detached process
# that no cygwin signal reaches — a `sleep 60` whose Windows process it
# suspends (NtSuspendProcess through powershell: the process's cygwin signal
# thread never runs again, TERM and KILL are lost; the shape of the two
# runners that outlived the gate's stop on 2026-10-22). Only the Windows side
# (`kill -f`, taskkill) ends it. Its argv[0] carries the fixture root; "PID
# WINPID" goes to TMPDIR/gfx-deaf.pid (the test's cleanup). Safety net: a
# hidden powershell (no cygwin process) holds a handle to it and, if it is
# still the process suspended (the same start time), ends it after 120 s if
# nothing else did (a killed test leaves no suspended process for long).
# Cygwin only: elsewhere nothing is left behind (the fixture is then a plain
# pass).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r /proc/$BASHPID/winpid ]]; then
    __gfx_t="${TMPDIR:-/tmp}"
    ( (exec -a "gfx-deaf:$SCRIPT_DIR" sleep 60) </dev/null >/dev/null 2>&1 & echo "$!" > "$__gfx_t/gfx-deaf.cpid" )
    read -r __gfx_p < "$__gfx_t/gfx-deaf.cpid"
    __gfx_w=""
    for (( __gfx_i = 0; __gfx_i < 50; __gfx_i++ )); do   # the exec done: <= 5 s
        __gfx_c=""; { IFS= read -r -d '' __gfx_c < "/proc/$__gfx_p/cmdline"; } 2>/dev/null
        [[ "$__gfx_c" == gfx-deaf:* ]] && { read -r __gfx_w < "/proc/$__gfx_p/winpid"; break; }
        sleep 0.1
    done
    if [[ "$__gfx_w" =~ ^[0-9]+$ ]]; then
        __gfx_ps="$(cygpath -u "${SYSTEMROOT:-C:\\Windows}" 2>/dev/null)/System32/WindowsPowerShell/v1.0/powershell.exe"
        [[ -x "$__gfx_ps" ]] || __gfx_ps=powershell.exe
        # The compile writes into %TEMP%: a Windows TEMP/TMP of its own (a bash
        # started from the other runtime may have none: then C:\Windows, denied).
        # .NET calls only, no cmdlet: a cmdlet's module autoload took 22-30 s
        # on windows-latest without the image's PSModuleAnalysisCachePath
        # (which a gate cell does not pass) — past this cell's 5 s (057)
        __gfx_tw="$(cygpath -w "${TMPDIR:-/tmp}" 2>/dev/null)"
        MSYS2_ARG_CONV_EXCL='*' TEMP="$__gfx_tw" TMP="$__gfx_tw" "$__gfx_ps" -NoProfile -NonInteractive -Command "\$o=[System.CodeDom.Compiler.CompilerParameters]::new(); \$o.GenerateInMemory=\$true; \$k=[Microsoft.CSharp.CSharpCodeProvider]::new().CompileAssemblyFromSource(\$o,'public static class KtW { [System.Runtime.InteropServices.DllImport(\"ntdll.dll\")] public static extern int NtSuspendProcess(System.IntPtr h); }').CompiledAssembly.GetType('KtW'); \$p=[Diagnostics.Process]::GetProcessById($__gfx_w); \$t=\$p.StartTime.Ticks; [void]\$k::NtSuspendProcess(\$p.Handle); \$s=[Diagnostics.ProcessStartInfo]::new('powershell.exe',('-NoProfile -NonInteractive -Command try{\$q=[Diagnostics.Process]::GetProcessById($__gfx_w)}catch{exit}; if(\$q.StartTime.Ticks -eq ' + \$t + ' -and -not \$q.WaitForExit(120000)){ \$q.Kill() }')); \$s.WindowStyle='Hidden'; [void][Diagnostics.Process]::Start(\$s)" </dev/null >/dev/null 2>&1
        printf '%s %s\n' "$__gfx_p" "$__gfx_w" > "$__gfx_t/gfx-deaf.pid"
    fi
fi
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture deaf" "$@"
