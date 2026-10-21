export const connectionsUsage = `Connected services (Linear, Notion, GitHub, Google…), shared by every local agent:
  harness connections                  open the Connectors page in the browser
  harness connections connect <code>   sign in from the terminal instead
  harness connections list [--json]    this computer's connections (no secrets)
  harness connections info <code>
  harness connections disconnect <code>
  harness connections add-key <name> <https-url>
                                       a service's API key, read from stdin, for Harness's cloud agents
                                       (Devin Cloud, Cursor Cloud); never given to the agents here
  harness connections refresh [<code>] renew tokens that are due (or this one now)
  harness connections sync             give Claude Code, Codex and OpenCode their MCP entries again
  harness connections call <code> <METHOD> <https-url> [--query K=V] [--json BODY|-] [--data K=V]
                                       [--form K=V|K=@file] [--header K:V]
                                       one REST request with the account's token, which you never see`
