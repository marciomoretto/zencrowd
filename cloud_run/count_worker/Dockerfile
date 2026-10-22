FROM python:3.11-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl ca-certificates && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN pip install --no-cache-dir --retries 5 --timeout 120 \
      --index-url https://download.pytorch.org/whl/cpu \
      --extra-index-url https://pypi.org/simple \
      torch torchvision

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Mesma revisao do P2PNet usada pela gem crowd_counting_p2pnet (ver Gemfile.lock).
ARG P2PNET_REF=9b16720302d9fb1a62cf499ec051237eb6b3da15
RUN mkdir -p /opt/p2pnet && \
    curl -fsSL "https://codeload.github.com/marciomoretto/CrowdCounting-P2PNet/tar.gz/${P2PNET_REF}" \
      | tar -xz --strip-components=1 -C /opt/p2pnet && \
    test -s /opt/p2pnet/weights/SHTechA.pth

ENV P2PNET_REPO=/opt/p2pnet
COPY worker.py /app/worker.py

CMD ["python", "/app/worker.py"]
