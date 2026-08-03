# Optional: GitHub OIDC → AWS deploy stub

This repo does **not** require AWS. To wire a real staging deploy later:

1. Create an IAM role trusting `token.actions.githubusercontent.com` for this repo
2. Attach least-privilege ECR + ECS (or EKS) permissions
3. Add a GitHub Environment `staging` with the role ARN
4. Uncomment the deploy job in `.github/workflows/ci.yml`

Example trust condition:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:sauravrana646/portfolio-secure-cicd:*"
    }
  }
}
```

Never store long-lived AWS access keys in GitHub Secrets for this pattern.
