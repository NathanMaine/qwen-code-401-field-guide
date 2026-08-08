#!/usr/bin/env bash
# Qwen Code setup audit — emits a diffable report. Never prints key material,
# only length / 6-char prefix / sha256[0:12].
#
#   ./qwen-audit.sh           # config report only
#   ./qwen-audit.sh --live    # also runs a real 8-token chat completion per endpoint
#
# Compare two machines:
#   ./qwen-audit.sh > this-machine.txt      # on each box
#   diff other-machine.txt this-machine.txt

set -uo pipefail
LIVE=0
[ "${1:-}" = "--live" ] && LIVE=1

echo "QWEN CODE AUDIT — $(hostname -s) — $(date '+%Y-%m-%d %H:%M')"
echo "======================================================================"

echo
echo "[1] ~/.qwen/settings.json"
python3 - <<'PY'
import json, os, hashlib
p = os.path.expanduser('~/.qwen/settings.json')
if not os.path.exists(p):
    print("  ABSENT"); raise SystemExit
d = json.load(open(p))
print(f"  $version            : {d.get('$version')}")
print(f"  auth.selectedType   : {d.get('security',{}).get('auth',{}).get('selectedType')}")
m = d.get('model', {})
print(f"  model.name          : {m.get('name')}")
print(f"  model.baseUrl       : {m.get('baseUrl')}")
env = d.get('env', {})
print(f"  env keys            : {len(env)}")
for k in sorted(env):
    s = str(env[k]).strip()
    h = hashlib.sha256(s.encode()).hexdigest()[:12]
    print(f"    {k}: len={len(s)} prefix6={s[:6]!r} sha256_12={h}")
print("  modelProviders:")
for fam, lst in sorted(d.get('modelProviders', {}).items()):
    for e in lst:
        inline = " INLINE_APIKEY!" if 'apiKey' in e else ""
        print(f"    [{fam}] {e.get('id'):<26} envKey={e.get('envKey'):<28} {e.get('baseUrl')}{inline}")
PY

echo
echo "[2] ~/.qwen/oauth_creds.json"
if [ -f ~/.qwen/oauth_creds.json ]; then
  python3 -c "
import json,os,datetime
d=json.load(open(os.path.expanduser('~/.qwen/oauth_creds.json')))
print('  EXISTS  fields:', sorted(d.keys()))
for k,v in d.items():
    if 'expir' in k.lower():
        print(f'  {k} = {v}')
        try:
            ts=float(v)/1000 if float(v)>1e12 else float(v)
            print('    ->', datetime.datetime.fromtimestamp(ts).isoformat())
        except Exception: pass
"
else
  echo "  ABSENT (api-key auth only)"
fi

echo
echo "[3] VSCode user settings — qwen-code.*"
for f in "$HOME/Library/Application Support/Code/User/settings.json" \
         "$HOME/Library/Application Support/Code - Insiders/User/settings.json"; do
  if [ -f "$f" ]; then
    hits=$(grep -n '"qwen-code\.' "$f")
    echo "  ${f##*/User/} :"
    [ -n "$hits" ] && echo "$hits" | sed 's/^/    /' || echo "    (none)"
  fi
done

echo
echo "[4] Versions"
for d in ~/.vscode/extensions ~/.vscode-insiders/extensions; do
  [ -d "$d" ] && ls "$d" | grep -i qwen | sed "s|^|  ext: |"
done
printf "  cli path   : %s\n" "$(command -v qwen || echo '(not on PATH)')"
command -v qwen >/dev/null && printf "  cli version: %s\n" "$(qwen --version 2>&1 | head -1)"
npm ls -g --depth=0 2>/dev/null | grep -i qwen | sed 's/^/  npm: /'

echo
echo "[5] Key material outside settings.json"
env | grep -oE '^(DASHSCOPE|QWEN|TOKEN_PLAN|BAILIAN)[A-Z_]*' | sort -u | sed 's/^/  shell env: /'
grep -lsE '(DASHSCOPE|QWEN|TOKEN_PLAN|BAILIAN)[A-Z_]*=' ~/.zshrc ~/.zshenv ~/.zprofile ~/.bash_profile ~/.qwen/.env 2>/dev/null | sed 's/^/  defined in: /'
echo "  (blank above = key lives only in ~/.qwen/settings.json)"

if [ "$LIVE" = "1" ]; then
  echo
  echo "[6] Live auth test — real chat completion, max_tokens 8"
  python3 - <<'PY'
import json, os, urllib.request, urllib.error
p = os.path.expanduser('~/.qwen/settings.json')
env = json.load(open(p)).get('env', {})
if not env:
    print("  no key in settings.env — skipping"); raise SystemExit
key = str(next(iter(env.values()))).strip()
targets = [
    ("https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen3.7-max"),
    ("https://coding-intl.dashscope.aliyuncs.com/v1/chat/completions", "qwen3-coder-plus"),
    ("https://dashscope-us.aliyuncs.com/compatible-mode/v1/chat/completions", "qwen-plus"),
]
for url, model in targets:
    body = json.dumps({"model": model, "max_tokens": 8,
                       "messages": [{"role": "user", "content": "Say OK"}]}).encode()
    req = urllib.request.Request(url, data=body, headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    host = url.split('/')[2]
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            print(f"  {host:<50} {model:<18} HTTP {r.status} OK")
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read()).get('error', {})
            code = err.get('code') if isinstance(err, dict) else err
        except Exception:
            code = '?'
        print(f"  {host:<50} {model:<18} HTTP {e.code} {code}")
    except Exception as e:
        print(f"  {host:<50} {model:<18} FAILED {type(e).__name__}")
PY
fi
