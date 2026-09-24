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

### 2. Create the Permissions Policy

The role's permissions are in
[`iam/github-actions-policy.json`](../../iam/github-actions-policy.json). The
policy is scoped to resources tagged `WorkflowRunId`, which every Packer and
workflow-created resource carries:

- **Create actions** (key pairs, security groups, launch templates, instances)
  require a non-empty `WorkflowRunId` tag in the request, so resources must be
  tagged on creation.
- **Mutating actions** (terminate, deregister, delete, `ModifyImageAttribute`,
  `CreateImage`) only apply to resources that already have a `WorkflowRunId`
  tag, so the role can't share, image, or delete anything else in the account.
- **`RunInstances`** can only launch Amazon-owned images or images built by the
  workflow, so the role can't boot a private AMI with its own key to read it.
  No statement allows `snapshot/*` for `RunInstances`, so a launch can't add a
  volume from an existing snapshot. The AMI's own root snapshot isn't
  evaluated, so normal launches still work.
- **`CreateImage`** only works on workflow-tagged instances, and only for
  snapshots that don't exist yet (`ec2:SnapshotTime` is null), so an image
  can't pull in an existing snapshot through an extra block device mapping.
- **`CreateTags`** is only allowed while creating a resource, on resources that
  already have a `WorkflowRunId` tag, or on spot instance requests (which Packer
  tags after launch). The role can't add `WorkflowRunId` to an existing
  resource to bring it into scope.
- No volume create/attach, snapshot attribute, or KMS permissions are granted.
  Encryption uses the `aws/ebs` key, whose key policy already allows EC2 to use
  it on the role's behalf.

Create the policy:

```bash
aws iam create-policy \
  --policy-name GitHubActions-PackerBuild-Policy \
  --policy-document file://iam/github-actions-policy.json
```

### 3. Create the IAM Role

The trust policy is in
[`iam/github-actions-trust-policy.json`](../../iam/github-actions-trust-policy.json).
Replace `YOUR_ACCOUNT_ID` and `YOUR_GITHUB_ORG`, then create the role and attach
the policy:

```bash
aws iam create-role \
  --role-name GitHubActions-PackerBuild \
  --assume-role-policy-document file://iam/github-actions-trust-policy.json

aws iam attach-role-policy \
  --role-name GitHubActions-PackerBuild \
  --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActions-PackerBuild-Policy
```

The trust policy only accepts tokens whose subject is either:

- `repo:ORG/packer-aws-windows-openssh:ref:refs/heads/main`: pushes to `main`,
  plus the scheduled and manual `cleanup-orphans.yml` runs
- `repo:ORG/packer-aws-windows-openssh:pull_request`: pull requests from
  branches in this repository

Forked pull requests and Dependabot runs don't receive an OIDC token or
secrets. IAM Access Analyzer warns about the `pull_request` subject because it
doesn't name a branch. That is expected, since pull request builds need it.
Anyone who can push a branch and open a pull request can still use the role,
which is why the permissions policy is scoped to workflow-tagged resources.
To require approval before pull request builds get AWS access, put the job in
a GitHub environment with required reviewers and change that subject to
`repo:ORG/packer-aws-windows-openssh:environment:NAME`.

#### Updating an Existing Role

To move an existing role to these policies, apply them after the workflow
changes that tag resources on creation are merged:

```bash
POLICY_ARN=arn:aws:iam::YOUR_ACCOUNT_ID:policy/GitHubActions-PackerBuild-Policy

# A managed policy keeps at most 5 versions; delete the oldest non-default one if needed
aws iam list-policy-versions --policy-arn "${POLICY_ARN}"

aws iam create-policy-version \
  --policy-arn "${POLICY_ARN}" \
  --policy-document file://iam/github-actions-policy.json \
  --set-as-default

# Save the current trust policy so it can be restored
aws iam get-role --role-name GitHubActions-PackerBuild \
  --query Role.AssumeRolePolicyDocument --output json > trust-policy-backup.json

aws iam update-assume-role-policy \
  --role-name GitHubActions-PackerBuild \
  --policy-document file://iam/github-actions-trust-policy.json
```

Then run a `main` build (`gh run rerun <run-id>` on the latest `main` run of
**Build and Test AMI**) and a pull request build (re-run the check on an open
pull request, or push to one), and check CloudTrail for denied calls:

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=GitHubActions \
  --query "Events[].CloudTrailEvent" --output json |
  jq -r '.[] | fromjson | select(.errorCode // "" | test("Unauthorized|AccessDenied")) | "\(.eventTime) \(.eventName) \(.errorCode)"'
```

To roll back, make the previous policy version the default again and restore
the saved trust policy:

```bash
aws iam set-default-policy-version --policy-arn "${POLICY_ARN}" --version-id PREVIOUS_VERSION

aws iam update-assume-role-policy \
  --role-name GitHubActions-PackerBuild \
  --policy-document file://trust-policy-backup.json
```

### 4. Add the Role ARN to GitHub Secrets

1. Copy the ARN of the IAM role you created (e.g.,
   `arn:aws:iam::123456789012:role/GitHubActions-PackerBuild`)
2. In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `AWS_ROLE_ARN`
5. Value: Paste the role ARN
6. Click **Add secret**

### 5. Scheduled Orphan Cleanup

The `cleanup-orphans.yml` workflow uses the same `AWS_ROLE_ARN` role. It runs
daily from the default branch (covered by the `ref:refs/heads/main` trust subject)
and deletes AMI build resources left behind by runs whose cleanup steps never
ran. It needs no permissions beyond the policy above. To preview what it would
delete, run it manually from the **Actions** tab (dry run is the default for
manual runs).

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

### "Access denied" or "UnauthorizedOperation" during EC2 operations

- Check that the IAM role has the policy from `iam/github-actions-policy.json`
  attached
- Check that the resource was created with a `WorkflowRunId` tag. The policy
  only allows creating tagged resources and changing resources that are
  already tagged, so a new step that creates a resource must pass
  `--tag-specifications` with `WorkflowRunId` instead of tagging it afterwards
- Use the CloudTrail query under [Updating an Existing Role](#updating-an-existing-role)
  to find the denied call

### Workflow doesn't trigger

- Ensure pull requests are targeting the `main` branch
- Check that GitHub Actions are enabled for the repository

## Cost Considerations

Each workflow run will:

- Build a Windows AMI (spot instance for ~15-30 minutes)
- Launch a test instance (t3a.xlarge for ~5 minutes)
- Delete all resources after testing

Estimated cost per run: **$0.50 - $1.00**

Consider limiting when this workflow runs if cost is a concern.

## Security Best Practices

1. **Principle of Least Privilege**: Only grant the minimum permissions
   needed
2. **Repository Restrictions**: Always restrict the trust policy to your
   specific repository
3. **Regular Audits**: Review CloudTrail logs for unexpected activity
4. **Block Public Sharing**: Block public sharing of AMIs and snapshots in
   each region you use (`aws ec2 enable-image-block-public-access
   --image-block-public-access-state block-new-sharing` and
   `aws ec2 enable-snapshot-block-public-access --state block-all-sharing`)
5. **Branch Protection**: Consider limiting this workflow to specific
   branches or requiring manual approval
6. **External Contributor Approval**: Configure GitHub Actions settings
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
