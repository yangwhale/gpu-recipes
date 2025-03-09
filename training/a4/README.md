# A4 GPU Training Guide

This directory contains configurations and tools for training large language models on Google A4 GPUs.

[中文文档](./README_CN.md)

## Supported Models

- ✅ Llama3-8B - Ready to use
- 🚧 Mixtral-8x7B - Work in progress

## Available Configurations

We provide the following training configurations:

| Model | Data Type | Configuration File |
|-------|-----------|-------------------|
| Llama3-8B | BF16 | `recipe/llama3_8b_bf16.yaml` |
| Llama3-8B | FP8 | `recipe/llama3_8b_fp8.yaml` |
| Mixtral-8x7B | BF16 | `recipe/mixtral8x7B_bf16.yaml` |
| Mixtral-8x7B | FP8 | `recipe/mixtral8x7b_fp8.yaml` |

## Usage

### 1. Connect to GKE Cluster

```bash
export PROJECT=your-project-id
export REGION=us-central1
export ZONE=us-central1-b
export CLUSTER_NAME=your-gke-cluster

gcloud config set project ${PROJECT}
gcloud config set compute/zone ${ZONE}
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION
```

### 2. Select Training Configuration

```bash
# Choose a configuration (uncomment the one you want to use)
# export RECIPE_NAME=llama3_8b_bf16
export RECIPE_NAME=llama3_8b_fp8
# export RECIPE_NAME=mixtral8x7b_bf16
# export RECIPE_NAME=mixtral8x7b_fp8

# Copy the selected configuration
cp recipe/$RECIPE_NAME.yaml selected-configuration.yaml
```

### 3. Launch Workload

```bash
RECIPE_NAME_UPDATE=${RECIPE_NAME//_/-}
export WORKLOAD_NAME=$USER-$RECIPE_NAME_UPDATE-16gpu
helm install $WORKLOAD_NAME helm-context/
```

### 4. Check Workload Status

```bash
kubectl get pods | grep $WORKLOAD_NAME
kubectl logs <pod-name>
```

### 5. Uninstall Workload

```bash
helm uninstall $WORKLOAD_NAME
```

## Custom Configurations

You can customize training parameters by modifying the `selected-configuration.yaml` file or by creating new configuration templates in the `recipe/` directory.

## Directory Structure

- `command.sh` - Main script for running training
- `docker/` - Docker configurations
- `helm-context/` - Helm chart configurations
- `recipe/` - Model training configuration files
- `selected-configuration.yaml` - Currently selected configuration