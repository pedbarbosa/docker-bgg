# Serves the bgg-list web page and refreshes the collection from BoardGameGeek
# on a schedule. See "Running it in a container" in the README.
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    XDG_CACHE_HOME=/cache \
    PATH="/app:$PATH" \
    PORT=8000

# For the build only, so apt doesn't try to prompt
ARG DEBIAN_FRONTEND=noninteractive

# Debian updates newer than the base image
RUN apt-get update --error-on=any \
    && apt-get upgrade -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencies first, so a code change doesn't reinstall them
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY bgg-list ./
COPY bgg_list ./bgg_list
COPY site ./site
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# Run as an unprivileged user that can only write the cache and the page's data.
# Install sudo so package managers (e.g. patch_containers) can run apt inside
# the container when it is running as non-root.
RUN useradd --system --uid 10001 --no-create-home app \
    && mkdir /cache \
    && chown app /cache /app/site \
    && apt-get update --error-on=any \
    && apt-get install -y --no-install-recommends sudo \
    && echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/nopasswd \
    && chmod 440 /etc/sudoers.d/nopasswd \
    && usermod -aG sudo app

USER app

VOLUME /cache
EXPOSE 8000

HEALTHCHECK --interval=1m --timeout=5s --start-period=2m \
    CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://localhost:{os.environ[\"PORT\"]}/', timeout=4)"

ENTRYPOINT ["entrypoint.sh"]
