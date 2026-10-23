---
display_name: Scratch Designer
description: OpenCode workspace with designer skills and Playwright MCP
icon: ../../../site/static/icon/coder.svg
maintainer_github: coder
verified: true
tags: [opencode, designer, playwright]
---

# Scratch Designer Template

OpenCode workspace with Docker-in-Docker, designer skills, and Playwright MCP.
Node.js 22.18+ and `npx` must be present in workspace image. Chromium is not
installed by this template.

Skills installed in every workspace:

```bash
npx --yes skills add emilkowalski/skills
npx --yes skills add pbakaus/impeccable
```

<!-- prerequisites:start -->

## Table of Contents

- [Prerequisites](#prerequisites)
- [Architecture](#architecture)

## Prerequisites

This template only provisions a Coder agent. You must provide your own compute platform (e.g. Docker, a VM, Kubernetes) for the agent to run on.

<!-- prerequisites:end -->

## Architecture

This template provisions the following resources:

- Coder agent (with CPU and RAM metadata)
- Environment variables for Git configuration

No infrastructure resources are included. Extend the template with your own compute resources.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.
