# Local AWS + OpenTofu Tutorial

This guide shows how to run a local AWS-compatible environment with Ministack, configure OpenTofu to use an S3 backend, and create a Kinesis stream.

## 1. Start Ministack

Run the local infrastructure defined in `compose.yaml`:

```bash
docker compose up -d
docker compose ps
```

Expected result:

```text
infra_ministack   ministackorg/ministack:latest   ...   Up ... (healthy)
```

Ministack exposes its AWS-compatible endpoint on `http://localhost:4566`.

## 2. Set AWS CLI environment variables

Point the AWS CLI and OpenTofu AWS provider to the local endpoint:

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

## 3. Create the S3 state bucket

Create the bucket that OpenTofu will use for remote state:

```bash
aws s3 mb s3://opentofu-state
aws s3 ls
```

Expected result:

```text
2026-04-26 ... opentofu-state
```

## 4. Initialize OpenTofu

Initialize the working directory so OpenTofu can use the S3 backend defined in `backend.tf`:

```bash
tofu init
```

This installs the AWS provider and creates `.terraform.lock.hcl`.

## 5. Create and select a workspace

Use the correct argument order when selecting a workspace:

```bash
tofu workspace select -or-create=true dev
tofu workspace show
```

Expected result:

```text
dev
```

Note: `tofu workspace select dev -or-create=true` is invalid. The flag must come before the workspace name.

## 6. Review the plan

Generate a plan to see what will be created:

```bash
tofu plan
```

The plan should show one resource:

```text
aws_kinesis_stream.test_stream
```

To save the plan for a deterministic apply:

```bash
tofu plan -out=out.tfplan
```

## 7. Apply the plan

Apply the saved plan:

```bash
tofu apply "out.tfplan"
```

This creates the Kinesis stream named `terraform-kinesis-test`.

## 8. Verify the stream

Confirm that the stream exists in the local environment:

```bash
aws kinesis list-streams
```

Expected result:

```json
{
  "StreamNames": ["terraform-kinesis-test"]
}
```

## What was created

- Local Ministack container on port `4566`
- S3 bucket named `opentofu-state`
- OpenTofu workspace `dev`
- Kinesis stream `terraform-kinesis-test`

## Troubleshooting

- If `aws s3 --help` fails, use `aws s3 help` instead.
- If OpenTofu says a workspace is empty, make sure you selected `dev` with `-or-create=true` before running `plan`.
