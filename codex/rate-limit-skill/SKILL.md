---
name: codex-rate-limit
summary: Report Codex usage percentage and refresh/reset time from local Codex session snapshots.
description: Use this skill when the user asks Codex to check current Codex rate-limit usage, token usage windows, usage percentage, remaining quota, reset time, refresh time, recovery time, 5-hour window, 7-day window, or asks “我还剩多少用量 / 什么时候恢复 / rate limit 什么时候刷新”. This skill reads local ~/.codex/sessions rollout JSONL files and runs scripts/codex_rate_limit.py to print a concise or JSON summary. Do not use it for API billing, ChatGPT web app limits, or non-Codex quota questions.
---

# Codex Rate Limit Skill

This skill reports the latest Codex rate-limit snapshot from local Codex session logs. It is script-backed and should be used whenever the task is about Codex usage percentage, reset time, refresh time, or recovery countdown.

## What this skill does

- Finds the newest `token_count` payload under `~/.codex/sessions/**/rollout-*.jsonl`.
- Reads `payload.rate_limits`.
- Prints:
  - plan type, when available;
  - reached limit type, when available;
  - primary window as `5h window`;
  - secondary window as `7d window`;
  - used percentage;
  - refresh countdown and local refresh time.

## When to run

Run this skill when the user asks things like:

- “查看 Codex 当前用量”
- “Codex 什么时候恢复 / 刷新？”
- “输出 5h / 7d 用量窗口”
- “rate limit 还剩多久？”
- “帮我看 Codex usage / reset time”

Do not run this skill for:

- OpenAI API billing or API quota;
- ChatGPT web app message limits;
- GitHub Copilot limits;
- cloud-side account usage that is not present in local Codex sessions.

## Workflow

1. Prefer the default command:

   ```bash
   python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py
   ```

2. For a compact one-line answer:

   ```bash
   python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py --short
   ```

3. For machine-readable output:

   ```bash
   python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py --json
   ```

4. If Codex sessions are stored elsewhere, pass the path explicitly:

   ```bash
   python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py \
     --sessions-dir /path/to/.codex/sessions
   ```

5. Summarize the result in Chinese by default when the user writes in Chinese. Keep the answer concise:

   ```text
   当前 Codex 用量：5h 窗口已用 72%，约 1h20m 后刷新；7d 窗口已用 34%，约 2d4h 后刷新。
   ```

## Error handling

If the script prints `No rate-limit snapshot found`, explain that no local Codex session rate-limit snapshot was found under the sessions directory. Suggest the user first run Codex once, or pass the correct `--sessions-dir`.

If a window is unavailable, report only the available fields and say the corresponding window was not present in the latest local snapshot.

## Notes

The script depends only on Python 3 standard library. No network access is required.
