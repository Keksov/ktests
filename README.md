# ktests — the kbool test framework

> Part of [kbool](https://github.com/Keksov/kbool): installation, quick start and the other components are there.

ktests is the bash test framework every kbool suite runs on:

* `ktest.sh`, which a test file sources: `kt_test_start` / `kt_test_pass` /
  `kt_test_fail`, the `kt_assert_*` helpers, and a fixture directory per test
  file that is removed at exit;
* `ktests.sh`, the suite runner: it finds a suite's `NNN_Name.sh` files, runs
  them threaded or one by one, and judges each file (a file that stops
  part-way is FAILED, not green with a lower total);
* `tools/gate.sh`, the phase gate: chosen suites under one or more bash
  runtimes, each suite in a sandbox of its own, one verdict line and exit code;
* `tools/strays.sh`, which finds and stops processes a run left behind.

It needs bash ≥ 5.1. It is developed and tested inside a kbool checkout:

```bash
git clone --recurse-submodules https://github.com/Keksov/kbool.git
cd kbool
bash ktests/tools/gate.sh all      # every suite of the tree under this bash
```

## Read next

* [docs/README.md](docs/README.md) — the framework guide: writing tests,
  fixtures, the runner, its options and verdicts
* [docs/START_HERE.md](docs/START_HERE.md) — a new suite in a few steps
* [docs/GATE_FOR_AGENTS.md](docs/GATE_FOR_AGENTS.md) — how to run the gate and
  read its result
* [tools/README.md](tools/README.md) — `gate.sh`, `strays.sh` and the other tools
* [CONTRIBUTING.md](CONTRIBUTING.md) — how to contribute
* [CHANGELOG.md](CHANGELOG.md) — the history

## License

MIT: see [LICENSE](LICENSE).
