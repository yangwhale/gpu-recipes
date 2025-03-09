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

### 2. Create and Configure GCS Bucket

Training jobs require access to a GCS bucket for storing and reading data. Follow these steps:

1. Create a GCS bucket (if you don't already have one):
   ```bash
   export GCS_BUCKET=your-bucket-name
   gsutil mb -l us-central1 gs://${GCS_BUCKET}
   ```

2. Edit the `helm-context/values.yaml` file to configure the GCS bucket mount:
   ```yaml
   # <GCS_BUCKET>: the name of your Cloud Storage bucket. Do not include the gs:// prefix
   jitGcsMount:
     bucketName: <GCS_BUCKET>
     mountPath: "/gcs"
   ```

3. If you don't need to use a GCS bucket, you can comment out this section and modify the `data` section in `selected-configuration.yaml` to use mock data:
   ```yaml
   data:
     data_impl: mock
     splits_string: 99990,8,2
     # ...other configuration...
     index_mapping_dir: null
     data_prefix: null
   ```

### 3. Select Training Configuration

```bash
# Choose a configuration (uncomment the one you want to use)
# export RECIPE_NAME=llama3_8b_bf16
export RECIPE_NAME=llama3_8b_fp8
# export RECIPE_NAME=mixtral8x7b_bf16
# export RECIPE_NAME=mixtral8x7b_fp8

# Copy the selected configuration
cp recipe/$RECIPE_NAME.yaml selected-configuration.yaml
```

### 4. Launch Workload

```bash
RECIPE_NAME_UPDATE=${RECIPE_NAME//_/-}
export WORKLOAD_NAME=$USER-$RECIPE_NAME_UPDATE-16gpu
helm install $WORKLOAD_NAME helm-context/
```

### 5. Check Workload Status

```bash
kubectl get pods | grep $WORKLOAD_NAME
kubectl logs <pod-name>
```

To continuously view logs, you can use the `-f` parameter:
```bash
kubectl logs -f <pod-name>
```

### 6. Uninstall Workload

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