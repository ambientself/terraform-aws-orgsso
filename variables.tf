variable "users" {
  description = "A nested map of users and properties.  The outer keys are usernames, and the inner properties map is documented in the User Properties section."
  type = map(object({
    full_name         = string
    email_address     = string
    group_memberships = list(string)
    tags              = map(string)
  }))
}

variable "permission_sets" {
  type = map(object({
    description               = string
    session_duration          = string
    aws_managed_policies_arns = list(string)
    customer_managed_policies = list(string)
    tags                      = map(string)
  }))
}

variable "groups" {
  type = map(object({
    description = string
  }))
}

variable "accounts" {
  type = map(object({
    account_id = string
    groups     = map(string)
  }))
}
