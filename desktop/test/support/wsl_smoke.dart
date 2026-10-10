/// An empty disposable-WSL smoke contract, for unit tests that pin WSL argv.
///
/// `WslRuntime` reads the `HARNESS_SMOKE_*` contract from
/// `Platform.environment` unless one is passed in. The live argv test
/// (`wsl_live_argv_test.dart`) asks a developer to export that contract, and
/// while it is exported every default runtime wraps its commands in the
/// admission script instead of `bash -lc`. Tests that pin the ordinary command
/// line pass this so their result does not depend on the shell they run from.
const noSmokeContract = <String, String>{};
