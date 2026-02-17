# AWS OIDC Setup for GitHub Actions

This document explains how to configure AWS IAM OIDC authentication for
the `build-and-test-ami.yml` workflow.

## Why OIDC?

OIDC (OpenID Connect) authentication is more secure than storing static
AWS credentials in GitHub Secrets because:

- No long-lived credentials to manage or rotate
- Temporary credentials with limited scope
- Better audit trail in AWS CloudTrail

## Setup Steps

### 1. Create an OIDC Identity Provider in AWS

1. Go to the AWS IAM Console
2. Navigate to **Identity providers** → **Add provider**
3. Configure the provider:
   - **Provider type**: OpenID Connect
   - **Provider URL**: `https://token.actions.githubusercontent.com`
   - **Audience**: `sts.amazonaws.com`
4. Click **Add provider**

### 2. Create an IAM Role for GitHub Actions

1. In the IAM Console, go to **Roles** → **Create role**
2. Select **Web identity** as the trusted entity type
3. Configure the trust policy:
   - **Identity provider**: Select the OIDC provider you just created
   - **Audience**: `sts.amazonaws.com`
4. Click **Next** and attach the following policies or create a custom
   policy with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:CreateFleet",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeImages",
        "ec2:CreateImage",
        "ec2:DeregisterImage",
        "ec2:DescribeSnapshots",
        "ec2:DeleteSnapshot",
        "ec2:CreateTags",
        "ec2:DescribeTags",
        "ec2:ModifyImageAttribute",
        "ec2:DescribeImageAttribute",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:CreateKeyPair",
        "ec2:ImportKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:DescribeKeyPairs",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeRegions",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeVolumes",
        "ec2:CreateVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:DeleteVolume"
      ],
      "Resource": "*"
    }
  ]
}
```

1. Name the role (e.g., `GitHubActions-PackerBuild`)
2. Click **Create role**

### 3. Update the Role Trust Policy

Edit the trust policy of the role you just created to restrict access to
your specific repository and `main` branch only (following the principle of
least privilege):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/packer-aws-windows-openssh:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

Replace:

- `YOUR_ACCOUNT_ID` with your AWS account ID
- `YOUR_GITHUB_ORG` with your GitHub organization or username

**Note**: This trust policy uses `StringEquals` for the `sub` condition to
restrict credentials to the `main` branch only. This prevents pull requests,
feature branches, and forked repositories from assuming the role, improving
security. For additional protection, GitHub Actions will skip the
`build-and-test` workflow for Dependabot PRs which lack secret access.

### 4. Add the Role ARN to GitHub Secrets

1. Copy the ARN of the IAM role you created (e.g.,
   `arn:aws:iam::123456789012:role/GitHubActions-PackerBuild`)
2. In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `AWS_ROLE_ARN`
5. Value: Paste the role ARN
6. Click **Add secret**

## Verification

To verify the setup is working:

1. Create a pull request to the `main` branch
2. The `build-and-test-ami.yml` workflow will automatically trigger
3. Check the workflow logs to ensure AWS authentication succeeds

## Troubleshooting

### "Not authorized to perform: sts:AssumeRoleWithWebIdentity"

- Verify the trust policy in your IAM role includes the correct GitHub
  repository
- Ensure the OIDC provider URL is exactly
  `https://token.actions.githubusercontent.com`

### "Access denied" during EC2 operations

- Check that the IAM role has all the necessary EC2 permissions
- Verify the policy is attached to the role

### Workflow doesn't trigger

- Ensure pull requests are targeting the `main` branch
- Check that GitHub Actions are enabled for the repository

## Cost Considerations

Each workflow run will:

- Build a Windows AMI (spot instance for ~15-30 minutes)
- Launch a test instance (t3.medium for ~5 minutes)
- Delete all resources after testing

Estimated cost per run: **$0.50 - $1.00**

Consider limiting when this workflow runs if cost is a concern.

## Security Best Practices

1. **Principle of Least Privilege**: Only grant the minimum permissions
   needed
2. **Repository Restrictions**: Always restrict the trust policy to your
   specific repository
3. **Regular Audits**: Review CloudTrail logs for unexpected activity
4. **Branch Protection**: Consider limiting this workflow to specific
   branches or requiring manual approval
5. **External Contributor Approval**: Configure GitHub Actions settings
   to require approval for all external contributors before workflows run.
   This prevents unauthorized access to AWS resources via forked PRs.
   Navigate to **Repository Settings** → **Actions** → **General** and
   enable **"Require approval for all outside collaborators"**

## Additional Resources

- [GitHub OIDC with AWS][github-oidc]
- [AWS IAM Roles for OIDC][aws-oidc]
- [Packer AWS Builder][packer-aws]

[github-oidc]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
[aws-oidc]: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
[packer-aws]: https://www.packer.io/plugins/builders/amazon/ebs
