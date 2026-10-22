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
        # Add-Type compiles into %TEMP%: a Windows TEMP/TMP of its own (a bash
        # started from the other runtime may have none: then C:\Windows, denied)
        __gfx_tw="$(cygpath -w "${TMPDIR:-/tmp}" 2>/dev/null)"
        MSYS2_ARG_CONV_EXCL='*' TEMP="$__gfx_tw" TMP="$__gfx_tw" "$__gfx_ps" -NoProfile -NonInteractive -Command "Add-Type -Name N -Namespace W -MemberDefinition '[DllImport(\"ntdll.dll\")] public static extern int NtSuspendProcess(IntPtr h);'; \$p=Get-Process -Id $__gfx_w; \$t=\$p.StartTime.Ticks; [void][W.N]::NtSuspendProcess(\$p.Handle); Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-NonInteractive','-Command',('\$q=Get-Process -Id $__gfx_w -EA 0; if(\$q -and \$q.StartTime.Ticks -eq ' + \$t + ' -and -not \$q.WaitForExit(120000)){ \$q.Kill() }')" </dev/null >/dev/null 2>&1
    fi
fi
__gfx_d="$SCRIPT_DIR"; while [[ "$__gfx_d" == */* && ! -f "$__gfx_d/ktests/ktests.sh" ]]; do __gfx_d="${__gfx_d%/*}"; done
exec "$__gfx_d/ktests/ktests.sh" "$SCRIPT_DIR" "gate fixture deafjob" "$@"
