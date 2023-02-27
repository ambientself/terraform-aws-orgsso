terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.33.0"
    }
  }
}

# Call AWS IAM SSO Info
data "aws_ssoadmin_instances" "orgsso" {}

####################
### Create SSO Users from terraform.tfvars users
####################

resource "aws_identitystore_user" "orgsso" {
  for_each = var.users

  identity_store_id = tolist(data.aws_ssoadmin_instances.orgsso.identity_store_ids)[0]

  display_name = each.value.full_name
  user_name    = each.value["email_address"]

  name {
    given_name  = element(split(" ", title(each.value.full_name)), 0)
    family_name = element(split(" ", title(each.value.full_name)), 1)
  }

  emails {
    primary = true
    value   = each.value["email_address"]
  }
}

####################
### Create SSO Groups from terraform.tfvars groups
####################

resource "aws_identitystore_group" "orgsso" {
  for_each = var.groups

  identity_store_id = tolist(data.aws_ssoadmin_instances.orgsso.identity_store_ids)[0]

  display_name = each.key
  description  = each.value["description"]
}

####################
### Create SSO PermissionSets from terraform.tfvars permissions_sets
####################
resource "aws_ssoadmin_permission_set" "orgsso" {
  for_each = var.permission_sets

  name             = each.key
  instance_arn     = tolist(data.aws_ssoadmin_instances.orgsso.arns)[0]
  session_duration = "PT${upper(each.value.session_duration)}"
  description      = each.value["description"]
}

####################
### Attach SSO Users to Groups
####################
# locals explained
# The code defines a local value usergroup that is a flattened list of user-group mappings.
# This list is created by looping over a variable var.users, which is a mapping of users to their group memberships.
# For each user and their group memberships, the code creates an object with two attributes: user and group.
# The resulting list of objects is then flattened.

locals {
  usergroup = flatten([
    for user, value in var.users : [
      for group in value["group_memberships"] : {
        user  = user
        group = group
      }
    ]
  ])
}

resource "aws_identitystore_group_membership" "orgsso" {
  for_each = {
    for user in local.usergroup :
    "${user.user}-${user.group}" => user
  }

  identity_store_id = tolist(data.aws_ssoadmin_instances.orgsso.identity_store_ids)[0]

  group_id = aws_identitystore_group.orgsso[each.value.group].group_id

  member_id = aws_identitystore_user.orgsso[each.value.user].user_id
}

####################
### Customer Managed Policies Attachment
####################
# locals explained
# The code uses a for loop to iterate over a variable named var.permission_sets,
# which is a mapping of groups to their customer-managed policies. For each group
# and its customer-managed policies, the code creates an object with two attributes: policy and group.
# The resulting list of objects is then flattened using the flatten function.

locals {
  customer_managed = flatten([
    for group, value in var.permission_sets : [
      for policy in value["customer_managed_policies"] : {
        policy = policy
        group  = group
      }
    ]
  ])
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "orgsso" {
  for_each = {
    for policy in local.customer_managed :
    "${policy.policy}-${policy.group}" => policy
  }

  instance_arn = tolist(data.aws_ssoadmin_instances.orgsso.arns)[0]

  permission_set_arn = aws_ssoadmin_permission_set.orgsso[each.value.group].arn

  customer_managed_policy_reference {
    name = each.value.policy
    path = "/"
  }
}

####################
### Managed Policies Attachment
####################
# locals explained
# The code uses a for loop to iterate over a variable named var.permission_sets,
# which is a mapping of groups to their AWS managed policies. For each group and its AWS managed policies,
# the code creates an object with two attributes: arn and group. The arn attribute represents the
# Amazon Resource Name (ARN) of the AWS managed policy, while the group attribute represents the group that
# the policy will be associated with. The resulting list of objects is then flattened using the flatten function.

locals {
  aws_managed = flatten([
    for group, value in var.permission_sets : [
      for arn in value["aws_managed_policies_arns"] : {
        arn   = arn
        group = group
      }
    ]
  ])
}

resource "aws_ssoadmin_managed_policy_attachment" "orgsso" {
  for_each = {
    for policy_arn in local.aws_managed :
    policy_arn.group => policy_arn
  }

  instance_arn = tolist(data.aws_ssoadmin_instances.orgsso.arns)[0]

  permission_set_arn = aws_ssoadmin_permission_set.orgsso[each.value.group].arn

  managed_policy_arn = each.value.arn
}

####################
### Account Assignment to Permissions Sets
####################
# locals explained
# The code uses a for loop to iterate over a variable named var.accounts, which is a list
# of AWS account structures. For each AWS account structure, the code loops over its groups attribute,
# which is a mapping of groups to their permissions. For each group and its permissions, the code creates
# an object with three attributes: account_id, group, and permissions. The account_id attribute represents
# the AWS account ID, the group attribute represents the group, and the permissions attribute represents
# the permissions that the group has. The resulting list of objects is then flattened using the flatten function.

locals {
  aws_accounts = flatten([
    for accounts in var.accounts : [
      for group, value in accounts.groups : {
        account_id  = accounts.account_id
        group       = group
        permissions = value

      }
    ]
  ])
}

resource "aws_ssoadmin_account_assignment" "orgsso" {
  depends_on = [aws_ssoadmin_customer_managed_policy_attachment.orgsso]

  for_each = { for id, group in local.aws_accounts : id => group }

  instance_arn = tolist(data.aws_ssoadmin_instances.orgsso.arns)[0]

  permission_set_arn = aws_ssoadmin_permission_set.orgsso[each.value.permissions].arn

  principal_id   = aws_identitystore_group.orgsso[each.value.group].group_id
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
}
