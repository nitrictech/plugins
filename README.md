# Official Cloud Infrastructure Plugins

A collection of official infrastructure-as-code plugins for seamless cloud resource provisioning across major cloud providers.

## Available Plugins

### AWS Plugins

- **CloudFront** - Content Delivery Network for fast, global content delivery with WAF and geo-restriction support
- **S3 Bucket** - Object storage for storing and retrieving data from anywhere
- **Lambda** - Run event-driven functions that execute on demand
- **Fargate** - Run containerized applications without managing servers
- **Load Balancer** - Distribute traffic across multiple targets
- **VPC** - Virtual Private Cloud for network isolation
- **IAM Role** - Manage access permissions for AWS resources

### GCP Plugins

- **Cloud Run** - Run stateless containers with automatic scaling from zero
- **Storage Bucket** - Object storage for files, images, and data
- **CDN** - Content delivery network for optimized content distribution
- **Service Account** - Manage identity and access for GCP resources

### Neon Plugin

- **Database** - Serverless PostgreSQL with instant branching, auto scaling, and built-in connection pooling

## Documentation Generation

To generate documentation for all plugins:

```bash
cd gen-docs
PLUGINS_DIR=.. DOCS_DIR=. python3 generate_plugin_docs.py
```

This will generate MDX documentation files in subdirectories (aws/, gcp/, neon/) within the gen-docs folder.
