export const apiUsage = `Saved APIs (Models → APIs):
  harness api list [--json]                 list connections, never keys
  harness api request <id> <path> [--method POST] [--data @file.json]
                                            call an API with its saved authentication
  harness api run <id> -- <command> [args]   give one tool its API key environment variable
                                            and HARNESS_API_BASE_URL; no engine login changes`
