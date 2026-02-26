```bash
export GITLAB_RUNNER_IMAGE_TAG=alpine-v17.9.1
export GITLAB_RUNNER_IMAGE_REPO=harness.jazziro.com/kubelab/cr/gitlab-runner
```

```bash
docker build -t $GITLAB_RUNNER_IMAGE_REPO:$GITLAB_RUNNER_IMAGE_TAG \
  --build-arg GITLAB_RUNNER_IMAGE_TAG=$GITLAB_RUNNER_IMAGE_TAG \
  -f Dockerfile .
```
