FROM python:3.11-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      ca-certificates \
      curl \
      libimage-exiftool-perl && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY cloud_run/render_worker/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --retries 5 --timeout 120 -r /app/requirements.txt

COPY lib/mosaico/mosaico_dji.py /app/mosaico_dji.py
COPY cloud_run/render_worker/worker.py /app/worker.py

CMD ["python", "/app/worker.py"]
