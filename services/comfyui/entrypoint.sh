#!/bin/bash
set -Eeuo pipefail

# --- 1. ディレクトリ作成 ---
mkdir -p ${WORKSPACE}/data/models/{checkpoints,clip,clip_vision,controlnet,diffusion_models,gligen,hypernetworks,loras,text_encoders,upscale,vae}

declare -A MOUNTS
MOUNTS["/root/.cache"]="${WORKSPACE}/data/.cache"
MOUNTS["${WORKSPACE}/input"]="${WORKSPACE}/data/config/input"
MOUNTS["/comfyui/output"]="${WORKSPACE}/output"

for to_path in "${!MOUNTS[@]}"; do
    set -Eeuo pipefail
    from_path="${MOUNTS[${to_path}]}"
    rm -rf "${to_path}"
    if [ ! -d "${from_path}" ]; then
        mkdir -vp "${from_path}"
    fi
    mkdir -vp "$(dirname "${to_path}")"
    ln -sT "${from_path}" "${to_path}"
    echo Mounted "$(basename "${from_path}")"
done

# --- 2. Python venv activate & exec ---
. ${VENV_PATH}/bin/activate

# --- 3. Print system info ---
echo "===== ComfyUI Entrypoint Info ====="
echo "Workspace: ${WORKSPACE}"
echo "Venv: ${VENV_PATH}"
echo "Python: $(which python) ($(python --version))"
echo "----- torch info -----"
python -c "import torch; print('torch=', torch.__version__); print('torch_cuda=', torch.version.cuda); print('avail=', torch.cuda.is_available())"

# --- 4. safetensors の自動ダウンロード機能 ---
DOWNLOAD_LIST="/container/download.list"
DOWNLOAD_DIR="${WORKSPACE}/data/models"

if [ -f "$DOWNLOAD_LIST" ]; then
    echo "${DOWNLOAD_LIST} found. Starting aria2c downloads..."
    mkdir -p "$DOWNLOAD_DIR"

    aria2c \
        --continue=true \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        --max-connection-per-server=4 \
        --split=16 \
        --dir="${DOWNLOAD_DIR}" \
        --input-file="${DOWNLOAD_LIST}"

    echo "Download finished."
else
    echo "No ${DOWNLOAD_LIST} found. Skipping download."
fi

CHECKSUM_LIST="/container/checksums.list"
if [ -f "$CHECKSUM_LIST" ]; then
    echo "${CHECKSUM_LIST} found. Starting sha256sum verification..."

    parallel --will-cite -a "${CHECKSUM_LIST}" "echo -n {} | sha256sum -c"

    echo "Checksum verification finished."
else
    echo "No ${CHECKSUM_LIST} found. Skipping checksum verification."
fi

# --- 5. startup.sh があれば実行 ---
if [ -f "${WORKSPACE}/data/config/startup.sh" ]; then
    pushd ${WORKSPACE}
    . ${WORKSPACE}/data/config/startup.sh
    popd
fi

# --- 6. コマンド実行 ---
exec "$@"
