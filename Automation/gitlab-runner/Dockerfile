ARG GITLAB_RUNNER_IMAGE_TAG=null
FROM gitlab-runner:${GITLAB_RUNNER_IMAGE_TAG}
RUN apk update && \
    apk upgrade && \
    mkdir -p /etc/gitlab-runner/
COPY ./config.toml /etc/gitlab-runner/config.toml