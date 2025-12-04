# Authentik PostgreSQL Configuration Mount Fix

## Problem

PostgreSQL container was crashing with error:
```
postgres: could not access the server configuration file "/bitnami/postgresql/conf/postgresql.conf": No such file or directory
```

## Root Cause

The Bitnami PostgreSQL Helm chart mounts the `postgresql-config` ConfigMap at `/bitnami/postgresql/data/conf` by default, but PostgreSQL was configured to look for the config at `/bitnami/postgresql/conf/postgresql.conf` via the startup args:

```yaml
args:
  - -c
  - config_file=/bitnami/postgresql/conf/postgresql.conf
```

This mismatch caused PostgreSQL to fail on startup.

## Solution

Added `extraVolumeMounts` to override the default config mount path in the Helm values:

```yaml
postgresql:
  primary:
    extraVolumeMounts:
      - name: postgresql-config
        mountPath: /bitnami/postgresql/conf
```

This mounts the ConfigMap at the location where PostgreSQL expects to find it.

## Applied Fix

Updated `/Users/jazziro/codesenju/repos/kubelab/addons/authentik.yaml` and redeployed via Ansible/ArgoCD.
