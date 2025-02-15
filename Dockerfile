# syntax = docker/dockerfile:1.3
ARG WORKER_CUDA_VERSION=11.8
FROM runpod/base:0.4.4-cuda${WORKER_CUDA_VERSION}.0 as builder

ARG WORKER_CUDA_VERSION=11.8 # Required duplicate to keep in scope

# Set Environment Variables
ENV WORKER_CUDA_VERSION=${WORKER_CUDA_VERSION} \
    HF_DATASETS_CACHE="/runpod-volume/huggingface-cache/datasets" \
    HUGGINGFACE_HUB_CACHE="/runpod-volume/huggingface-cache/hub" \
    TRANSFORMERS_CACHE="/runpod-volume/huggingface-cache/hub" \
    HF_TRANSFER=1


# Install Python dependencies
COPY builder/requirements.txt /requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    python3.11 -m pip install --upgrade pip && \
    python3.11 -m pip install --upgrade -r /requirements.txt && \
    rm /requirements.txt

# Install torch and vllm based on CUDA version
RUN if [[ "${WORKER_CUDA_VERSION}" == 11.8* ]]; then \
        python3.11 -m pip install -U --force-reinstall torch==2.1.2 xformers==0.0.23.post1 --index-url https://download.pytorch.org/whl/cu118; \
        python3.11 -m pip install -e git+https://github.com/runpod/vllm-fork-for-sls-worker.git@cuda-11.8#egg=vllm; \
    else \
        python3.11 -m pip install -e git+https://github.com/runpod/vllm-fork-for-sls-worker.git#egg=vllm; \
    fi && \
    rm -rf /root/.cache/pip

# Add source files
COPY src .

# Setup for Option 2: Building the Image with the Model included
ARG MODEL_NAME=""
ARG MODEL_BASE_PATH="/runpod-volume/"
ARG QUANTIZATION=""

ENV MODEL_BASE_PATH=$MODEL_BASE_PATH \
    MODEL_NAME=$MODEL_NAME \
    QUANTIZATION=$QUANTIZATION 

RUN --mount=type=secret,id=HF_TOKEN,required=false \
    if [ -f /run/secrets/HF_TOKEN ]; then \
        export HF_TOKEN=$(cat /run/secrets/HF_TOKEN); \
    fi && \
    if [ -n "$MODEL_NAME" ]; then \
        python3.11 /download_model.py --model $MODEL_NAME; \
    fi

# Start the handler
CMD ["python3.11", "/handler.py"]
