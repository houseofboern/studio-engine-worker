#!/bin/bash
# Link the Runpod-cached Hugging Face repo (CACHE_REPO) into ComfyUI's model folders, then start the stock worker.
# 2026-11-22: RunPod's cache keeps the repo as it was when cached (MEASURED: Dwarf LoRAs added later were missing),
# so at boot any loras/ file in the live repo that the cache lacks is downloaded straight from Hugging Face (small files).
set -u
C=$(ls -d /runpod-volume/huggingface-cache/hub/models--${CACHE_REPO//\//--}/snapshots/*/ 2>/dev/null | head -1)
if [ -z "$C" ]; then echo "PRESTART_FAIL: cached repo $CACHE_REPO not found"; ls -la /runpod-volume /runpod-volume/huggingface-cache/hub 2>&1 | head -20; sleep 5; exit 1; fi
M=/comfyui/models
for d in diffusion_models text_encoders vae loras; do
  mkdir -p "$M/$d"
  for f in "$C$d"/*; do [ -e "$f" ] && ln -sf "$(readlink -f "$f")" "$M/$d/$(basename "$f")"; done
done
# Python (proven present: the Dockerfile runs it) instead of curl, which may be missing from the base image.
python - <<'PY' || { echo "PRESTART_FETCH_STEP_FAILED"; touch "$M/loras/ZZ_FETCH_ERR_python_step_failed.safetensors"; }
import json, os, urllib.request
repo, tok, d = os.environ['CACHE_REPO'], os.environ.get('HF_TOKEN', ''), '/comfyui/models/loras'
h = {'Authorization': 'Bearer ' + tok} if tok else {}
import re
# A failure shows up as a fake LoRA name, so it appears in ComfyUI's "not in list" error (worker logs are hard to reach).
mark = lambda why: open(os.path.join(d, 'ZZ_FETCH_ERR_' + re.sub(r'[^A-Za-z0-9]+', '_', str(why))[:80] + '.safetensors'), 'w').close()
get = lambda u, t=30: urllib.request.urlopen(urllib.request.Request(u, headers=h), timeout=t)
try:
    names = [x['path'].split('/')[-1] for x in json.load(get(f'https://huggingface.co/api/models/{repo}/tree/main/loras')) if x['path'].endswith('.safetensors')]
except Exception as e:
    mark('list_' + str(e)); raise
print('PRESTART_LIVE_LORAS', len(names), flush=True)
for n in names:
    dst = os.path.join(d, n)
    if os.path.exists(dst): continue
    try:
        with get(f'https://huggingface.co/{repo}/resolve/main/loras/{n}', 600) as r, open(dst + '.part', 'wb') as f:
            while True:
                c = r.read(8 << 20)
                if not c: break
                f.write(c)
        os.replace(dst + '.part', dst); print('PRESTART_FETCHED', n, flush=True)
    except Exception as e:
        print('PRESTART_FETCH_FAIL', n, e, flush=True)
        mark(f'{n[:20]}_{e}')
        if os.path.exists(dst + '.part'): os.remove(dst + '.part')
PY
echo "PRESTART_OK from $C"; ls -l $M/diffusion_models $M/text_encoders $M/vae $M/loras
exec /start.sh
