---
name: terraform-style-guide-security
description: Generate Terraform HCL code following HashiCorp's security practices
---

<!-- Vendored from https://github.com/hashicorp/agent-skills
     (terraform/code-generation/skills/terraform-style-guide).
     Licensed under the Mozilla Public License 2.0 — see ./LICENSE.
     This Source Code Form is subject to the terms of the Mozilla Public
     License, v. 2.0. If a copy of the MPL was not distributed with this
     file, You can obtain one at https://mozilla.org/MPL/2.0/. -->

# Terraform Style Guide - Security

When generating code, apply security hardening:

- Enable encryption at rest by default
- Configure private networking where applicable
- Apply principle of least privilege for security groups
- Enable logging and monitoring
- Never hardcode credentials or secrets
- Mark sensitive outputs with `sensitive = true`
- Use `ephemeral` resources and write-only attributes
  for sensitive data when possible

## Example: Secure S3 Bucket

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "${var.project}-${var.environment}-data"
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

## Ephemeral resources

Ephemeral resources prevent sensitive data being stored in state.
For more information on ephemeral resources, see the
[Terraform documentation](https://developer.hashicorp.com/terraform/language/block/ephemeral).

Before you generate code for an ephemeral resource, check that the Terraform
version is greater than or equal to 1.11.0.

Then, follow this priority order for managing sensitive attributes:

1. **First priority: Native secrets manager integration**
   If a resource has the ability to automatically manage a sensitive attribute by
   storing it in a secrets manager (e.g., AWS Secrets Manager, Azure Key Vault),
   use that configuration. This is the preferred approach.

   ```hcl
   # Bad
   resource "aws_rds_cluster" "example" {
     cluster_identifier = "example"
     database_name      = "test"
     master_username    = "test"
     master_password    = var.db_master_password
   }
   ```

   ```hcl
   # Good - password managed by Secrets Manager and rotated automatically
   resource "aws_rds_cluster" "example" {
     cluster_identifier = "example"
     database_name      = "test"
     master_username    = "test"
     manage_master_user_password = true
   }
   ```

2. **Second priority: Ephemeral resources and write-only attributes**
   When a native secrets manager integration is not available, use ephemeral
   resources in combination with write-only attributes. The ephemeral resource
   retrieves the secret at apply time and passes it to the write-only attribute.
   The value never gets persisted in state.

   ```hcl
   ephemeral "random_password" "db_master_password" {
     length  = 32
     special = true
   }

   resource "aws_rds_cluster" "example" {
     cluster_identifier = "example"
     database_name      = "test"
     master_username    = "test"
     master_password_wo = ephemeral.random_password.db_master_password.result
   }
   ```

3. **Third priority: Sensitive variables**
   Mark the variable as `sensitive = true`. The value is stored in state.

   ```hcl
   variable "db_master_password" {
     type      = string
     sensitive = true
   }

   resource "aws_rds_cluster" "example" {
     cluster_identifier = "example"
     database_name      = "test"
     master_username    = "test"
     master_password    = var.db_master_password
   }
   ```
