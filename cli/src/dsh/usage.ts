export function dshUsage(): string {
  return `Domain-specific harnesses (a DSH turns Harness into a product for one domain — see store/README.md):
  harness dsh list                 what is installed on this computer, and what the registry offers
  harness dsh install <id|url|path> [--ref <ref>] [--path <folder>] [--link]
                                   install by registry id (autonomous/typst), git URL, or local path;
                                   --path installs one folder of that repo (store/agents/typst);
                                   --link symlinks a local checkout instead of cloning it
  harness dsh doctor <id>          re-run the harness's own readiness check
  harness dsh update <id>          update a package, preserving its workspaces
  harness dsh remove <id>          uninstall (a --link install removes only the link)
  harness dsh check <path>         conformance check for a harness checkout (what the registry runs)`
}
