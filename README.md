<p align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/logo/suga-dark.svg">
      <source media="(prefers-color-scheme: light)" srcset="docs/logo/suga-light.svg">
      <img width="120" alt="Shows a black logo in light color mode and a white one in dark color mode." src="docs/logo/suga-light.svg">
    </picture>
</p>

<p align="center">
  <a href="https://docs.addsuga.com">Documentation</a> •
  <a href="https://github.com/nitrictech/suga/releases">Releases</a>
</p>

# Suga Infrastructure Plugins

Terraform modules that provide a consistent interface for provisioning cloud resources across AWS, GCP, Azure (coming soon) and Neon.

## Plugin Categories

- **Storage** - Object storage buckets (AWS S3, GCP Storage)
- **Compute** - Serverless functions and containers (AWS Lambda, AWS Fargate, GCP Cloud Run)
- **Database** - Managed databases (Neon PostgreSQL)
- **CDN** - Content delivery networks (AWS CloudFront, GCP CDN)
- **Networking** - Load balancers and VPCs (AWS only)
- **Identity** - IAM roles and service accounts (AWS IAM Role, GCP Service Account)

## What These Plugins Do

- Pre-built Terraform modules for common cloud resources
- Automatic dependency resolution - services get the IAM roles or service accounts they need
- Outputs include connection details your application needs (endpoints, credentials, etc.)
- (Optional) Go SDKs for exposing resources to client applications
