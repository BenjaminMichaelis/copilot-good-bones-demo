# Sourced by the guardrail hooks so one script serves both Copilot CLI (and
# the Copilot app, which runs on its engine) and VS Code's Local agent.
# Bash port of hook-compat.ps1; see its header for the two payload formats.
#
#   hook_normalize  rewrites a VS Code payload in $payload into the CLI shape
#                   the hooks already check ({toolName, toolArgs, cwd, ...}).
#   hook_result     prints a result given in the CLI's top-level shape, wrapped
#                   in hookSpecificOutput when VS Code is the caller.

HOOK_HOST=cli
HOOK_EVENT=""

hook_normalize() {
  if ! jq -e 'has("hook_event_name")' >/dev/null 2>&1 <<<"$payload"; then
    return 0
  fi
  HOOK_HOST=vscode
  HOOK_EVENT="$(jq -r '.hook_event_name' <<<"$payload")"
  payload="$(jq -c '
    (.tool_input // {}) as $in
    | (if .tool_name == "run_in_terminal" then {toolName: "bash", toolArgs: {command: ($in.command // "")}}
       elif .tool_name == "apply_patch" then {toolName: "apply_patch", toolArgs: ($in.input // "")}
       elif .tool_name == "create_file" then {toolName: "create", toolArgs: {path: $in.filePath, file_text: $in.content}}
       elif .tool_name == "replace_string_in_file" then {toolName: "edit", toolArgs: {path: $in.filePath, new_str: $in.newString}}
       elif .tool_name == "insert_edit_into_file" then {toolName: "edit", toolArgs: {path: $in.filePath, new_str: $in.code}}
       elif .tool_name == "edit_notebook_file" then {toolName: "edit", toolArgs: {path: $in.filePath, new_str: $in.newCode}}
       elif .tool_name == "multi_replace_string_in_file" then
         [$in.replacements[]?.filePath | strings] as $paths
         | {toolName: "edit", toolArgs: {
             path: (([$paths[] | select(test("\\.(cs|csproj)$"))] | first) // $paths[0] // ""),
             new_str: ([$in.replacements[]?.newString | strings] | join("\n"))}}
       else {toolName: .tool_name, toolArgs: $in} end)
    + {cwd: .cwd, sessionId: .session_id, stop_hook_active: (.stop_hook_active // false), displayName: .tool_name}
  ' <<<"$payload")"
}

hook_result() {
  if [ "$HOOK_HOST" = "vscode" ]; then
    jq -c --arg event "$HOOK_EVENT" '{hookSpecificOutput: ({hookEventName: $event} + .)}' <<<"$1"
  else
    printf '%s\n' "$1"
  fi
}
