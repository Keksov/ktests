# Contributing to ktests

ktests is a submodule of [kbool](https://github.com/Keksov/kbool), and its
tests need the whole tree. The full guide — the one test command, what CI
checks, what the verdicts mean, the house rules — is
[kbool's CONTRIBUTING.md](https://github.com/Keksov/kbool/blob/main/CONTRIBUTING.md).

Work in the `ktests/` folder of a kbool checkout
(`git clone --recurse-submodules https://github.com/Keksov/kbool.git`) and send
the pull request here, against `main`.

* The suite is `tests/` — gate suite id `ktests`. Every suite runs on this
  framework, so a ktests change is checked with every suite: from the kbool
  root, `bash ktests/tools/gate.sh all`.
* The runner and the assertions: [docs/README.md](docs/README.md); the gate,
  `strays.sh` and the platform layer: [tools/README.md](tools/README.md).
* The gate's own tests (`tests/050_GateCli.sh` … `057_GateDeafStop.sh`) use the
  suites under `tests/gate_fixtures/` as data — those are not test files of this suite.
* `tests/058_Bash51Hazards.sh` checks the bash 5.1 floor over the non-test code.
* CI: `.github/workflows/ci.yml` runs kbool's 13 rows with your PR in place of
  ktests; the checks are named `kbool / linux (debian 13)` and so on.
