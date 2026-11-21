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
AUTH=(); [ -n "${HF_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $HF_TOKEN")
LIVE=$(curl -sf -m 20 "${AUTH[@]}" "https://huggingface.co/api/models/$CACHE_REPO/tree/main/loras" \
  | python3 -c "import json,sys; [print(x['path'].split('/')[-1]) for x in json.load(sys.stdin) if x['path'].endswith('.safetensors')]" 2>/dev/null)
for n in $LIVE; do
  [ -e "$M/loras/$n" ] && continue
  if curl -sfL -m 300 "${AUTH[@]}" -o "$M/loras/$n.part" "https://huggingface.co/$CACHE_REPO/resolve/main/loras/$n"; then
    mv "$M/loras/$n.part" "$M/loras/$n"; echo "PRESTART_FETCHED $n"
  else rm -f "$M/loras/$n.part"; echo "PRESTART_FETCH_FAIL $n"; fi
done
echo "PRESTART_OK from $C"; ls -l $M/diffusion_models $M/text_encoders $M/vae $M/loras
exec /start.sh
