# Copy to ~/.steampipe/config/aws.spc. Holds profile names only, never keys.
# The aggregator is named "aws" so it sorts before its members and answers unqualified table names.
connection "aws" {
  plugin      = "aws"
  type        = "aggregator"
  connections = ["aws_*"]
}

connection "aws_prod" {
  plugin  = "aws"
  profile = "ledger-prod"     # a profile in ~/.aws/config that assumes the read-only role
  regions = ["*"]
}

connection "aws_dev" {
  plugin  = "aws"
  profile = "ledger-dev"
  regions = ["*"]
}

# Do NOT add ignore_error_codes = ["AccessDenied", ...] to these connections.
# It turns "not allowed to look" into "nothing there", and the report would look clean.
