# Copy to ~/.steampipe/config/gcp.spc. Uses Application Default Credentials.
connection "gcp" {
  plugin      = "gcp"
  type        = "aggregator"
  connections = ["gcp_*"]
}

connection "gcp_prod" {
  plugin  = "gcp"
  project = "REPLACE-WITH-PROJECT-ID"
}
