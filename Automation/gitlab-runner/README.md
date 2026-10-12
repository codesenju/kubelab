```bash
export GITLAB_RUNNER_IMAGE_TAG=alpine-v17.9.1
export GITLAB_RUNNER_IMAGE_REPO=harness.homelab.com/kubelab/cr/gitlab-runner
export GITLAB_RUNNER_TOKEN='<runner-token-from-gitlab>'
```

Register runner with `GITLAB_RUNNER_TOKEN` at deployment time. Do not store token in
`config.toml` or commit generated runner configuration.

```bash
docker build -t $GITLAB_RUNNER_IMAGE_REPO:$GITLAB_RUNNER_IMAGE_TAG \
  --build-arg GITLAB_RUNNER_IMAGE_TAG=$GITLAB_RUNNER_IMAGE_TAG \
  -f Dockerfile .
```
