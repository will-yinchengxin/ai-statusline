# codex-rate-limit skill

用于给 Codex 查询本地 session 中记录的 rate-limit 用量和恢复/刷新时间。

## 安装

```bash
mkdir -p ~/.codex/skills
cp -R codex-rate-limit-skill ~/.codex/skills/codex-rate-limit
chmod +x ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py
```

然后重启 Codex CLI/IDE。

## 使用

在 Codex 中直接问：

```text
使用 codex-rate-limit skill，帮我查看当前用量和恢复时间
```

或手动运行：

```bash
python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py
python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py --short
python3 ~/.codex/skills/codex-rate-limit/scripts/codex_rate_limit.py --json
```
