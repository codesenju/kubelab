#!/bin/bash

# Script to push to both GitHub and Gitea with different ignore rules

# Check if branch name is provided
if [ -z "$1" ]; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD)
  echo "No branch specified, using current branch: $BRANCH"
else
  BRANCH=$1
  echo "Using specified branch: $BRANCH"
fi

# Push to GitHub (uses .gitignore)
echo "Pushing to GitHub..."
git push origin $BRANCH

# Push to Gitea (uses .gitea-ignore via .gitea-config)
echo "Pushing to Gitea..."
git push gitea $BRANCH

echo "Push completed to both remotes."
