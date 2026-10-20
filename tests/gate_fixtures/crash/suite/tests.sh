#!/bin/bash
# gate fixture "crash" (gate G2): the runner dies without writing its summary
# (SIGKILL to itself) — verdict CRASH
echo "gate fixture crash: the runner is about to die"
kill -KILL $$
