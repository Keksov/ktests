#!/usr/bin/env bash
# gate fixture "deadstart" (launch L2.7-G, 3c): the wrapper never starts the
# runner — it execs `sleep 600`, the picture of a runner wedged at its start
# (no output, no test file's shell). The gate's start grace
# (KT_GATE_START_GRACE) must stop it as TIMEOUT `runner did not start`, long
# before --timeout.
exec sleep 600
