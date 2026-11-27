# Base images come from Amazon ECR Public (the official Docker "python" image, mirrored by AWS),
# never from Docker Hub: no Docker Hub rate limits, and every image in this project comes from AWS.
# No "# syntax=" line on purpose: it would pull the BuildKit frontend from Docker Hub.
ARG BASE_IMAGE=public.ecr.aws/docker/library/python:3.14-slim-trixie

# ---- build stage: install dependencies into a virtualenv ----
FROM ${BASE_IMAGE} AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install -r requirements.txt \
 && /venv/bin/pip uninstall -y pip

# ---- runtime stage: no compilers, no pip, non-root ----
FROM ${BASE_IMAGE}
ENV PATH="/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# Apply Debian security fixes released after the base image was built, and drop pip:
# the app never installs packages at runtime, and pip vendors its own (often vulnerable) libraries.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip \
 && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app
COPY --from=build /venv /venv
WORKDIR /app
COPY app.py store.py aws_auth.py migrate.py telemetry.py rag.py gunicorn.conf.py ./
COPY certs/ certs/
USER 10001
EXPOSE 8080 9464
# /tmp is an emptyDir in Kubernetes so the root filesystem can stay read-only
# (gunicorn worker files and the merged Prometheus metrics live there).
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app:app"]
