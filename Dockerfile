ARG BASE=kitty-base:local
FROM ${BASE}
# 2026-11-22 shared engine: one worker for create (Krea 2), edit (Flux 3 Klein), pose/carousel (MiniMax H3 Image) and the
# finish pass (Qwen 2.1 tiled skin, AusBoss nodes). H3 Image needs ComfyUI f99de883 (2026-11-21), newer than release 0.42.1.
ARG COMFY_COMMIT=f99de883d5e65317c7f4a4b617b5aa7936622029
ARG AUSBOSS_COMMIT=9ab4365245b33a8927ecd2d7c747fc4c7e6a76b1
RUN git clone -q --filter=blob:none https://github.com/comfyanonymous/ComfyUI /tmp/cu && cd /tmp/cu && git checkout -q ${COMFY_COMMIT} \
 && rm -rf .git && cp -a /tmp/cu/. /comfyui/ && cd /comfyui && rm -rf /tmp/cu && uv pip install --python /opt/venv/bin/python -r /comfyui/requirements.txt \
 && git clone -q https://github.com/ausboss/ComfyUI-AusBoss /comfyui/custom_nodes/ComfyUI-AusBoss \
 && cd /comfyui/custom_nodes/ComfyUI-AusBoss && git checkout -q ${AUSBOSS_COMMIT} \
 && { [ -f requirements.txt ] && uv pip install --python /opt/venv/bin/python -r requirements.txt || true; }
COPY prestart.sh /prestart.sh
# Fail the build if any node a recipe needs is missing.
RUN chmod +x /prestart.sh && cd /comfyui && /opt/venv/bin/python -c "import comfy, torch, comfy_aimdo, importlib.metadata as m; print('torch', torch.__version__, 'aimdo', m.version('comfy-aimdo')); assert m.version('comfy-aimdo') == '0.6.0'" \
 && grep -rq "MiniMaxH3ImageConditioning" comfy_extras comfy_api_nodes comfy 2>/dev/null \
 && grep -rq "ReferenceMultiLatent" comfy_extras && grep -rq "Flux2Scheduler" comfy_extras && echo NODES_OK
CMD ["/prestart.sh"]
