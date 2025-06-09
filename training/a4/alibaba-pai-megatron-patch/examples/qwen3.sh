#!/bin/bash

PAI_WORKSPACE=${PAI_WORKSPACE_ROOT:-/mnt} #默认值是/mnt

# -----------------------------------------------------------------------------
# 功能1: 克隆 Pai-Megatron-Patch 代码库
# -----------------------------------------------------------------------------
if [[ "${SKIP_CLONE_REPO}" != "true" && "$JOB_COMPLETION_INDEX" -eq "0" ]]; then
  echo "Step 1: Cloning Pai-Megatron-Patch repository..."
  cd $PAI_WORKSPACE
  git clone --recurse-submodules https://github.com/alibaba/Pai-Megatron-Patch.git
else
  echo "Step 1: Skipping repository cloning (SKIP_CLONE_REPO=true or not rank 0)"
fi

# -----------------------------------------------------------------------------
# 功能2: 下载模型和数据集
# -----------------------------------------------------------------------------
if [[ "${SKIP_DOWNLOAD_DATA}" != "true" && "$JOB_COMPLETION_INDEX" -eq "0" ]]; then
  echo "Step 2: Downloading models and datasets..."
  cd $PAI_WORKSPACE
  mkdir -p qwen-ckpts
  huggingface-cli download Qwen/Qwen3-30B-A3B --local-dir $PAI_WORKSPACE/qwen-ckpts/Qwen3-30B-A3B
  
  mkdir -p qwen-datasets
  cd qwen-datasets
  wget https://atp-modelzoo-wlcb-pai.oss-cn-wulanchabu.aliyuncs.com/release/models/pai-megatron-patch/qwen-datasets/mmap_qwen3_datasets_text_document.bin
  wget https://atp-modelzoo-wlcb-pai.oss-cn-wulanchabu.aliyuncs.com/release/models/pai-megatron-patch/qwen-datasets/mmap_qwen3_datasets_text_document.idx
  wget https://atp-modelzoo-wlcb-pai.oss-cn-wulanchabu.aliyuncs.com/release/models/pai-megatron-patch/datasets/alpaca_zh-train-general.json
  wget https://atp-modelzoo-wlcb-pai.oss-cn-wulanchabu.aliyuncs.com/release/models/pai-megatron-patch/datasets/alpaca_zh-valid-general.json
else
  echo "Step 2: Skipping data download (SKIP_DOWNLOAD_DATA=true or not rank 0)"
fi

# 创建唯一的同步目录 (仅使用JOB_ID)
SYNC_DIR="$PAI_WORKSPACE/sync_flags_${JOB_ID}"

# 节点0完成下载后创建标记文件
if [[ "$JOB_COMPLETION_INDEX" -eq "0" ]]; then
  echo "Creating unique sync directory and flag file to signal other nodes..."
  mkdir -p $SYNC_DIR
  touch $SYNC_DIR/download_complete_flag
fi

# 所有非0节点等待节点0完成下载
if [[ "$JOB_COMPLETION_INDEX" -ne "0" ]]; then
  echo "Node $JOB_COMPLETION_INDEX waiting for node 0 to complete downloads..."
  while [[ ! -f $SYNC_DIR/download_complete_flag ]]; do
    sleep 5
    echo "Still waiting for download to complete on node 0..."
  done
  echo "Download complete flag detected, proceeding with checkpoint conversion."
fi

# -----------------------------------------------------------------------------
# 功能3: 检查点转换
# -----------------------------------------------------------------------------
if [[ "${SKIP_CHECKPOINT_CONVERSION}" != "true" ]]; then
  echo "Step 3: Converting checkpoints..."
  cd $PAI_WORKSPACE/Pai-Megatron-Patch/toolkits/distributed_checkpoints_convertor
  OMP_NUM_THREADS=12 WORLD_SIZE=$NNODES RANK=$JOB_COMPLETION_INDEX bash scripts/qwen3/run_8xH20.sh \
  A3B \
  $PAI_WORKSPACE/qwen-ckpts/Qwen3-30B-A3B \
  $PAI_WORKSPACE/qwen-ckpts/Qwen3-30B-A3B-to-mcore  \
  false \
  true \
  bf16
else
  echo "Step 3: Skipping checkpoint conversion (SKIP_CHECKPOINT_CONVERSION=true)"
fi

# -----------------------------------------------------------------------------
# 功能4: 运行训练
# -----------------------------------------------------------------------------
if [[ "${SKIP_TRAINING}" != "true" ]]; then
  echo "Step 4: Starting training..."
  cd $PAI_WORKSPACE/Pai-Megatron-Patch/examples/qwen3
  #因为在pai-megatron-patch的脚本中拿WORLD_SIZE的值当node数量用，拿 RANK当node Rank用因此调用前做特殊复制操作
  OMP_NUM_THREADS=12 WORLD_SIZE=$NNODES \
  RANK=$JOB_COMPLETION_INDEX \
  KUBERNETES_CONTAINER_RESOURCE_GPU=$GPUS_PER_NODE \
  sh run_mcore_qwen3.sh  \
  dlc  \
  A3B   \
  1    \
  8 \
  1e-5   \
  1e-6   \
  128  \
  128  \
  bf16  \
  4   \
  2  \
  1 \
  1 \
  4 \
  true \
  true   \
  true \
  false \
  sel   \
  false \
  100000  \
  $PAI_WORKSPACE/qwen-datasets/mmap_qwen3_datasets_text_document   \
  $PAI_WORKSPACE/qwen-datasets/mmap_qwen3_datasets_text_document   \
  $PAI_WORKSPACE/qwen-ckpts/Qwen3-30B-A3B-to-mcore  \
  10000  \
  100   \
  $PAI_WORKSPACE/logs/output_mcore_qwen3_pretrain
else
  echo "Step 4: Skipping training (SKIP_TRAINING=true)"
fi

echo "Qwen3 setup and training script completed!"